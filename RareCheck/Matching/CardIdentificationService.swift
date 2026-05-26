import UIKit

// MARK: - Card Identification Service
//
// Orchestration:
//  1. Run OCR + card detection in parallel
//  2. Score OCR match against local name index
//  3. Score pHash against cached artwork hashes
//  4. Combine: confidence = 0.6 * ocrScore + 0.4 * hashScore
//  5. If confidence >= 0.70 → resolve locally (no network)
//  6. If confidence < 0.70 → send to backend API

@MainActor
final class CardIdentificationService: ObservableObject {
    static let shared = CardIdentificationService()

    private let ocrService = OCRService.shared
    private let cardDetector = CardDetector.shared
    private let pHashMatcher = PHashMatcher.shared
    private let api = APIClient.shared

    private let localConfidenceThreshold: Double = 0.70
    private let ocrWeight: Double = 0.60
    private let hashWeight: Double = 0.40

    // MARK: - Public Entry Point

    func identify(image: UIImage) async throws -> IdentificationResult {
        let start = Date()

        // Step 1: Detect and crop card from image. If we cannot find a
        // trading-card rectangle, do not send a random room photo to lookup.
        guard let cardImage = await cardDetector.detectAndCrop(from: image) else {
            throw CardIdentificationError.noCardDetected
        }

        // Step 2: Run OCR + pHash concurrently
        async let ocrResult = ocrService.extractCardInfo(from: cardImage)
        async let imageHash = Task.detached(priority: .userInitiated) { [weak self] in
            self?.pHashMatcher.hash(of: cardImage)
        }.value

        let (ocr, hash) = try await (ocrResult, imageHash)
        let candidateNames = fallbackNameCandidates(from: ocr)

        guard !candidateNames.isEmpty else {
            throw CardIdentificationError.noReadableCardText
        }

        // Step 3: Attempt local resolution
        if let localMatches = await localMatch(ocr: ocr, imageHash: hash),
           !localMatches.isEmpty,
           localMatches[0].confidence >= localConfidenceThreshold {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return IdentificationResult(matches: localMatches, source: .local, processingTimeMs: ms)
        }

        // Step 4: Fall back to API
        let compressed = cardImage.jpegData(compressionQuality: 0.55) ?? Data()
        let hints = CardIdentifyOCRHints(
            name: ocr.name,
            collectorNumber: ocr.collectorNumber,
            setCode: ocr.setCode,
            rawText: ocr.rawText
        )
        var apiResponse = try await api.identifyCard(imageData: compressed, ocrHints: hints)

        if apiResponse.matches.isEmpty {
            for candidate in candidateNames {
                guard candidate.caseInsensitiveCompare(ocr.name ?? "") != .orderedSame else { continue }
                let candidateHints = CardIdentifyOCRHints(
                    name: candidate,
                    collectorNumber: ocr.collectorNumber,
                    setCode: ocr.setCode,
                    rawText: nil
                )
                let candidateResponse = try await api.identifyCard(imageData: compressed, ocrHints: candidateHints)
                if !candidateResponse.matches.isEmpty {
                    apiResponse = candidateResponse
                    break
                }
            }
        }

        guard !apiResponse.matches.isEmpty else {
            throw CardIdentificationError.noPokemonMatch(candidateNames)
        }

        let ms = Int(Date().timeIntervalSince(start) * 1000)
        return IdentificationResult(matches: apiResponse.matches, source: .api, processingTimeMs: ms)
    }

    // MARK: - Local Matching

    private func localMatch(ocr: OCRCardInfo, imageHash: UInt64?) async -> [CardMatch]? {
        // Load local card index (name → cardId mappings cached on first launch)
        guard let index = LocalCardIndex.shared.index else { return nil }

        var candidates: [(card: LocalCardRecord, score: Double)] = []

        for record in index {
            var score = 0.0

            // OCR scoring
            if let name = ocr.name {
                let nameScore = stringSimilarity(name.lowercased(), record.name.lowercased())
                score += nameScore * ocrWeight
            }
            if let num = ocr.collectorNumber, record.collectorNumber == num {
                score += 0.1
            }
            if let setCode = ocr.setCode, record.setCode.lowercased() == setCode.lowercased() {
                score += 0.1
            }

            // pHash scoring
            if let queryHash = imageHash, let storedHash = record.pHash {
                let hashScore = pHashMatcher.similarity(between: queryHash, and: storedHash)
                score += hashScore * hashWeight
            }

            if score > 0.3 { candidates.append((record, score)) }
        }

        guard !candidates.isEmpty else { return nil }

        let top3 = candidates
            .sorted { $0.score > $1.score }
            .prefix(3)

        return top3.map { item in
            CardMatch(
                id: item.card.id,
                name: item.card.name,
                setName: item.card.setName,
                setCode: item.card.setCode,
                collectorNumber: item.card.collectorNumber,
                rarity: item.card.rarity,
                imageURL: item.card.imageURL,
                confidence: min(item.score, 1.0),
                price: item.card.lastKnownPrice ?? PriceData.zero
            )
        }
    }

    // MARK: - String Similarity (Jaro-Winkler)

    private func stringSimilarity(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b { return 1 }
        let aChars = Array(a)
        let bChars = Array(b)
        let matchRange = max(aChars.count, bChars.count) / 2 - 1
        var aMatches = [Bool](repeating: false, count: aChars.count)
        var bMatches = [Bool](repeating: false, count: bChars.count)
        var matches = 0
        var transpositions = 0

        for i in 0..<aChars.count {
            let start = max(0, i - matchRange)
            let end = min(i + matchRange + 1, bChars.count)
            for j in start..<end {
                if bMatches[j] || aChars[i] != bChars[j] { continue }
                aMatches[i] = true; bMatches[j] = true; matches += 1; break
            }
        }

        if matches == 0 { return 0 }

        var k = 0
        for i in 0..<aChars.count {
            if !aMatches[i] { continue }
            while !bMatches[k] { k += 1 }
            if aChars[i] != bChars[k] { transpositions += 1 }
            k += 1
        }

        let m = Double(matches)
        let jaro = (m / Double(aChars.count) + m / Double(bChars.count) + (m - Double(transpositions) / 2) / m) / 3

        // Winkler prefix bonus
        var prefix = 0
        for i in 0..<min(4, min(aChars.count, bChars.count)) {
            if aChars[i] == bChars[i] { prefix += 1 } else { break }
        }
        return jaro + Double(prefix) * 0.1 * (1 - jaro)
    }

    private func fallbackNameCandidates(from ocr: OCRCardInfo) -> [String] {
        var seen = Set<String>()
        var candidates: [String] = []

        func add(_ value: String?) {
            guard let value = value else { return }
            let cleaned = cleanNameCandidate(value)
            guard let cleaned, !seen.contains(cleaned.lowercased()) else { return }
            seen.insert(cleaned.lowercased())
            candidates.append(cleaned)
        }

        add(ocr.name)
        ocr.rawText
            .components(separatedBy: .newlines)
            .forEach { add($0) }

        return candidates.prefix(8).map { $0 }
    }

    private func cleanNameCandidate(_ value: String) -> String? {
        let cleaned = value
            .replacingOccurrences(of: #"[^A-Za-z0-9 '.:-]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\bHP\s*\d+\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\b\d{1,3}\s*/\s*\d{1,3}\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleaned.count >= 3, cleaned.count <= 60 else { return nil }
        guard cleaned.range(of: #"^\d+$"#, options: .regularExpression) == nil else { return nil }
        guard cleaned.range(of: #"^(basic|stage\s+\d+|trainer|energy|weakness|resistance|retreat)$"#, options: [.regularExpression, .caseInsensitive]) == nil else {
            return nil
        }
        return cleaned
    }
}

// MARK: - Local Card Index

final class LocalCardIndex {
    static let shared = LocalCardIndex()
    var index: [LocalCardRecord]?

    private let cacheURL: URL = {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rarecheck_local_index.json")
    }()

    init() { loadFromDisk() }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: cacheURL),
              let records = try? JSONDecoder().decode([LocalCardRecord].self, from: data) else {
            index = []
            return
        }
        index = records
    }

    func update(with records: [LocalCardRecord]) {
        index = records
        try? JSONEncoder().encode(records).write(to: cacheURL)
    }
}

struct LocalCardRecord: Codable {
    let id: String
    let name: String
    let setName: String
    let setCode: String
    let collectorNumber: String
    let rarity: String
    let imageURL: String
    let pHash: UInt64?
    let lastKnownPrice: PriceData?
}

extension PriceData {
    static let zero = PriceData(low: 0, mid: 0, high: 0, market: 0, currency: "USD", updatedAt: Date())
}

// MARK: - Scanner ViewModel

@MainActor
final class CardScannerViewModel: ObservableObject {
    @Published var isDetecting = false
    @Published var isLocked = false
    @Published var lockProgress = 0.0
    @Published var isProcessing = false
    @Published var identificationResult: IdentificationResult?
    @Published var lastError: String?

    // Auto-capture: when a card is detected continuously for this many
    // consecutive analyze ticks (~0.5s each), fire the shutter automatically
    // by toggling `shouldAutoCapture`. The view observes and triggers capture.
    @Published var shouldAutoCapture = false

    private let identificationService = CardIdentificationService.shared
    private let persistenceController = PersistenceController.shared

    private var frameThrottle = 0
    private var consecutiveDetections = 0
    private let lockThreshold = 2  // quick but stable enough to avoid room photos

    func analyzeFrame(_ buffer: CVPixelBuffer) {
        frameThrottle += 1
        guard frameThrottle % 6 == 0 else { return }  // Check about 5x/sec at 30fps
        let hasCard = CardDetector.shared.hasCard(in: buffer)
        Task { @MainActor in
            self.isDetecting = hasCard
            if hasCard {
                self.consecutiveDetections = min(self.consecutiveDetections + 1, self.lockThreshold)
            } else {
                self.consecutiveDetections = 0
            }
            self.isLocked = self.consecutiveDetections >= self.lockThreshold
            self.lockProgress = Double(self.consecutiveDetections) / Double(self.lockThreshold)
        }
    }

    func identify(image: UIImage) async {
        guard !isProcessing else { return }
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        do {
            let result = try await identificationService.identify(image: image)
            identificationResult = result
        } catch let scanError as CardIdentificationError {
            lastError = scanError.errorDescription ?? "Card scan failed."
            print("[RareCheck] Identification scan gate: \(scanError)")
        } catch let urlError as URLError {
            lastError = "Couldn't reach identification service (\(urlError.code.rawValue)). Backend may be offline."
            print("[RareCheck] Identification URLError: \(urlError)")
        } catch let apiError as APIError {
            lastError = apiError.errorDescription ?? "Card lookup service returned an error."
            print("[RareCheck] Identification APIError: \(apiError)")
        } catch {
            lastError = "Identification failed: \(error.localizedDescription)"
            print("[RareCheck] Identification error: \(error)")
        }
    }

    func saveCard(_ card: CardMatch) {
        persistenceController.saveCard(card)
    }
}

extension IdentificationResult: Identifiable {
    var id: String { "\(processingTimeMs)-\(matches.first?.id ?? "unknown")" }
}

enum CardIdentificationError: LocalizedError {
    case noCardDetected
    case noReadableCardText
    case noPokemonMatch([String])

    var errorDescription: String? {
        switch self {
        case .noCardDetected:
            return "No trading card was captured. Align one card inside the frame until the border turns green, then scan again."
        case .noReadableCardText:
            return "I found a card shape, but couldn't read a Pokemon card name. Move closer, reduce glare, and hold steady until READY."
        case .noPokemonMatch(let candidates):
            let names = candidates.prefix(3).joined(separator: ", ")
            if names.isEmpty {
                return "No Pokemon database match found. Try moving closer and keeping the card flat in the frame."
            }
            return "No Pokemon database match found for: \(names). Try moving closer, reducing glare, and centering the card name."
        }
    }
}
