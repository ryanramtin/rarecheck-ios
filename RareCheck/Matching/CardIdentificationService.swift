import UIKit

// MARK: - Card Identification Service
//
// Orchestration:
//  1. Run OCR + card detection in parallel
//  2. Score OCR match against local name index
//  3. Score pHash when cached artwork hashes are available
//  4. Resolve locally when OCR/hash evidence is strong enough
//  5. Fall back to the backend API for uncertain matches

@MainActor
final class CardIdentificationService: ObservableObject {
    static let shared = CardIdentificationService()

    private let ocrService = OCRService.shared
    private let cardDetector = CardDetector.shared
    private let pHashMatcher = PHashMatcher.shared
    private let api = APIClient.shared

    private let localConfidenceThreshold: Double = 0.70
    private let localTextOnlyConfidenceThreshold: Double = 0.62
    private let localRescueConfidenceThreshold: Double = 0.78
    private let apiConfidenceThreshold: Double = 0.70
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
        let pHashMatcher = self.pHashMatcher
        async let ocrResult = ocrService.extractCardInfo(from: cardImage)
        async let imageHash = Task.detached(priority: .userInitiated) {
            pHashMatcher.hash(of: cardImage)
        }.value

        let (ocr, hash) = try await (ocrResult, imageHash)
        let candidateNames = fallbackNameCandidates(from: ocr)
        let localRescueMatches = LocalCardIndex.shared.bestOCRRescueMatches(
            candidateNames: candidateNames,
            collectorNumber: ocr.collectorNumber,
            setCode: ocr.setCode
        )

        guard !candidateNames.isEmpty else {
            throw CardIdentificationError.noReadableCardText
        }

        // Step 3: Attempt local resolution
        if let localMatches = await localMatch(ocr: ocr, imageHash: hash),
           !localMatches.isEmpty,
           shouldTrustLocalMatch(localMatches[0], ocr: ocr, imageHash: hash) {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return IdentificationResult(matches: localMatches, source: .local, processingTimeMs: ms)
        }

        if let bestRescue = localRescueMatches.first,
           bestRescue.confidence >= localRescueConfidenceThreshold {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            print("[RareCheck] Resolved locally via OCR rescue candidates")
            return IdentificationResult(matches: localRescueMatches, source: .local, processingTimeMs: ms)
        }

        // Step 4: Fall back to API. Use the cleaned name candidates in
        // priority order instead of first sending the full OCR blob. That
        // avoids slow, low-quality DB searches for attacks like "Scratch"
        // before the actual Pokemon name.
        let lookupImage = cardImage.resizedForRareCheckLookup(maxDimension: 900)
        let compressed = lookupImage.jpegData(compressionQuality: 0.48) ?? Data()
        let apiCandidates = Array(candidateNames.prefix(4))
        print("[RareCheck] Pokemon DB candidates: \(apiCandidates)")
        var apiResponse = CardIdentifyResponse(matches: [], processingTimeMs: 0)

        do {
            for candidate in apiCandidates {
                let candidateStart = Date()
                let candidateHints = CardIdentifyOCRHints(
                    name: candidate,
                    collectorNumber: ocr.collectorNumber,
                    setCode: ocr.setCode,
                    rawText: nil
                )
                let candidateResponse = try await api
                    .identifyCard(imageData: compressed, ocrHints: candidateHints)
                    .filtered(minConfidence: apiConfidenceThreshold)
                let elapsed = Int(Date().timeIntervalSince(candidateStart) * 1000)
                print("[RareCheck] Pokemon DB lookup '\(candidate)' returned \(candidateResponse.matches.count) confident matches in \(elapsed)ms")
                if !candidateResponse.matches.isEmpty {
                    apiResponse = candidateResponse
                    break
                }
            }
        } catch {
            if !localRescueMatches.isEmpty {
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                print("[RareCheck] API lookup failed; using local OCR rescue candidates")
                return IdentificationResult(matches: localRescueMatches, source: .local, processingTimeMs: ms)
            }
            throw error
        }

        guard !apiResponse.matches.isEmpty else {
            if !localRescueMatches.isEmpty {
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                print("[RareCheck] API returned no confident matches; showing local OCR rescue candidates")
                return IdentificationResult(matches: localRescueMatches, source: .local, processingTimeMs: ms)
            }
            throw CardIdentificationError.noConfidentPokemonMatch(candidateNames)
        }

        let ms = Int(Date().timeIntervalSince(start) * 1000)
        return IdentificationResult(matches: apiResponse.matches, source: .api, processingTimeMs: ms)
    }

    // MARK: - Local Matching

    private func localMatch(ocr: OCRCardInfo, imageHash: UInt64?) async -> [CardMatch]? {
        // Load local card index (name → cardId mappings cached on first launch)
        guard let index = LocalCardIndex.shared.index else { return nil }

        let normalizedOCRName = ocr.name.map(Self.normalizedCardText)
        let nameCounts = Dictionary(grouping: index, by: { Self.normalizedCardText($0.name) })
            .mapValues(\.count)

        var candidates: [(card: LocalCardRecord, score: Double, hasHashEvidence: Bool)] = []

        for record in index {
            var score = 0.0
            var hasHashEvidence = false

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
                hasHashEvidence = true
            } else if isStrongTextOnlyMatch(
                record: record,
                normalizedOCRName: normalizedOCRName,
                ocr: ocr,
                nameCounts: nameCounts
            ) {
                // Downloaded Pokemon TCG records do not include local artwork
                // hashes yet. Let strong unique text evidence carry local
                // lookup instead of always falling through to the API.
                score += 0.04
            }

            if score > 0.3 { candidates.append((record, score, hasHashEvidence)) }
        }

        guard !candidates.isEmpty else { return nil }

        let top3 = candidates
            .sorted {
                if $0.score == $1.score { return $0.card.name < $1.card.name }
                return $0.score > $1.score
            }
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
                confidence: min(item.score, item.hasHashEvidence ? 1.0 : 0.90),
                price: item.card.lastKnownPrice ?? PriceData.zero
            )
        }
    }

    private func shouldTrustLocalMatch(_ match: CardMatch, ocr: OCRCardInfo, imageHash: UInt64?) -> Bool {
        if match.confidence >= localConfidenceThreshold {
            return true
        }

        guard imageHash != nil,
              match.confidence >= localTextOnlyConfidenceThreshold,
              let record = LocalCardIndex.shared.index?.first(where: { $0.id == match.id }) else {
            return false
        }

        let normalizedOCRName = ocr.name.map(Self.normalizedCardText)
        let nameCounts = Dictionary(grouping: LocalCardIndex.shared.index ?? [], by: { Self.normalizedCardText($0.name) })
            .mapValues(\.count)
        return isStrongTextOnlyMatch(
            record: record,
            normalizedOCRName: normalizedOCRName,
            ocr: ocr,
            nameCounts: nameCounts
        )
    }

    private func isStrongTextOnlyMatch(
        record: LocalCardRecord,
        normalizedOCRName: String?,
        ocr: OCRCardInfo,
        nameCounts: [String: Int]
    ) -> Bool {
        guard let normalizedOCRName,
              normalizedOCRName == Self.normalizedCardText(record.name) else {
            return false
        }

        if let number = ocr.collectorNumber, !number.isEmpty, record.collectorNumber == number {
            return true
        }
        if let setCode = ocr.setCode, !setCode.isEmpty, record.setCode.caseInsensitiveCompare(setCode) == .orderedSame {
            return true
        }

        return nameCounts[normalizedOCRName, default: 0] == 1
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

        return candidates.prefix(6).map { $0 }
    }

    private static func normalizedCardText(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^a-zA-Z0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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
        guard cleaned.range(of: #"^[0-9 .:-]"#, options: .regularExpression) == nil else { return nil }
        guard cleaned.range(of: #"\s\d+\b"#, options: .regularExpression) == nil else { return nil }
        let letters = cleaned.filter(\.isLetter).count
        let digits = cleaned.filter(\.isNumber).count
        guard letters >= 3, digits <= 1 else { return nil }
        guard cleaned.range(of: #"^(basic|stage\s+\d+|trainer|energy|weakness|resistance|retreat)$"#, options: [.regularExpression, .caseInsensitive]) == nil else {
            return nil
        }
        guard cleaned.range(of: #"^(scratch|live coal|call for family|tail whip|ember|tackle|quick attack|flamethrower|fire spin|attached energy|does damage|this attack|during your next turn|opponent|active pokemon|bench|evolves from|illus\.?|no\.)$"#, options: [.regularExpression, .caseInsensitive]) == nil else {
            return nil
        }
        guard cleaned.range(of: #"\b(weakness|resistance|retreat|damage|opponent|energy attached|your turn|coin|discard|bench|evolves from|illus\.?|©|tm)\b"#, options: [.regularExpression, .caseInsensitive]) == nil else {
            return nil
        }
        guard cleaned.range(of: #"^(basic\s+)?(grass|fire|water|lightning|psychic|fighting|darkness|metal|fairy|dragon)?\s*energy$"#, options: [.regularExpression, .caseInsensitive]) == nil else {
            return nil
        }
        return cleaned
    }
}

private extension UIImage {
    func resizedForRareCheckLookup(maxDimension: CGFloat) -> UIImage {
        let largestSide = max(size.width, size.height)
        guard largestSide > maxDimension, largestSide > 0 else { return self }

        let scale = maxDimension / largestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

private extension CardIdentifyResponse {
    func filtered(minConfidence: Double) -> CardIdentifyResponse {
        CardIdentifyResponse(
            matches: matches.filter { $0.confidence >= minConfidence },
            processingTimeMs: processingTimeMs
        )
    }
}

// MARK: - Local Card Index

final class LocalCardIndex {
    static let shared = LocalCardIndex()
    var index: [LocalCardRecord]?

    private let seedResourceName = "rarecheck_card_index_seed"
    private let refreshInterval: TimeInterval = 7 * 24 * 60 * 60
    private var isRefreshing = false

    private let cacheURL: URL = {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rarecheck_local_index.json")
    }()

    init() { loadFromDisk() }

    private func loadFromDisk() {
        if let data = try? Data(contentsOf: cacheURL),
           let records = try? JSONDecoder().decode([LocalCardRecord].self, from: data),
           !records.isEmpty {
            index = records
            return
        }

        if let records = loadBundledSeed(), !records.isEmpty {
            index = records
            return
        }

        index = []
    }

    func update(with records: [LocalCardRecord]) {
        index = records
        try? JSONEncoder().encode(records).write(to: cacheURL)
    }

    var recordCount: Int {
        index?.count ?? 0
    }

    var isUsingBundledSeed: Bool {
        recordCount > 0 && (try? FileManager.default.attributesOfItem(atPath: cacheURL.path)) == nil
    }

    func searchCards(matching query: String, limit: Int = 80) -> [CardMatch] {
        let normalizedQuery = Self.normalizedSearchText(query)
        guard !normalizedQuery.isEmpty, let index else { return [] }
        let terms = normalizedQuery.split(separator: " ").map(String.init)

        return index
            .compactMap { record -> (record: LocalCardRecord, score: Int)? in
                let name = Self.normalizedSearchText(record.name)
                let set = Self.normalizedSearchText(record.setName)
                let number = Self.normalizedSearchText(record.collectorNumber)
                let code = Self.normalizedSearchText(record.setCode)
                let haystack = "\(name) \(set) \(number) \(code)"

                guard terms.allSatisfy({ haystack.contains($0) }) else { return nil }

                var score = 0
                if name == normalizedQuery { score += 100 }
                if name.hasPrefix(normalizedQuery) { score += 60 }
                if name.contains(normalizedQuery) { score += 35 }
                if number == normalizedQuery || code == normalizedQuery { score += 30 }
                score += max(0, 20 - name.count / 4)
                return (record, score)
            }
            .sorted {
                if $0.score == $1.score { return $0.record.name < $1.record.name }
                return $0.score > $1.score
            }
            .prefix(limit)
            .map { item in
                CardMatch(
                    id: item.record.id,
                    name: item.record.name,
                    setName: item.record.setName,
                    setCode: item.record.setCode,
                    collectorNumber: item.record.collectorNumber,
                    rarity: item.record.rarity,
                    imageURL: item.record.imageURL,
                    confidence: 1,
                    price: item.record.lastKnownPrice ?? .zero
                )
            }
    }

    func bestOCRRescueMatches(
        candidateNames: [String],
        collectorNumber: String?,
        setCode: String?,
        limit: Int = 3
    ) -> [CardMatch] {
        guard !candidateNames.isEmpty else { return [] }

        let normalizedCollector = collectorNumber.map(Self.normalizedSearchText) ?? ""
        let normalizedSetCode = setCode.map(Self.normalizedSearchText) ?? ""
        var bestByID: [String: CardMatch] = [:]

        for candidate in candidateNames {
            let normalizedCandidate = Self.normalizedSearchText(candidate)
            guard !normalizedCandidate.isEmpty else { continue }

            for result in searchCards(matching: candidate, limit: 12) {
                let normalizedName = Self.normalizedSearchText(result.name)
                var confidence = baseRescueConfidence(candidate: normalizedCandidate, resultName: normalizedName)
                guard confidence > 0 else { continue }

                if !normalizedCollector.isEmpty,
                   normalizedCollector == Self.normalizedSearchText(result.collectorNumber) {
                    confidence += 0.18
                }
                if !normalizedSetCode.isEmpty,
                   normalizedSetCode == Self.normalizedSearchText(result.setCode) {
                    confidence += 0.10
                }
                if normalizedName == normalizedCandidate {
                    confidence += 0.04
                }

                let enriched = CardMatch(
                    id: result.id,
                    name: result.name,
                    setName: result.setName,
                    setCode: result.setCode,
                    collectorNumber: result.collectorNumber,
                    rarity: result.rarity,
                    imageURL: result.imageURL,
                    confidence: min(confidence, 0.98),
                    price: result.price
                )

                if let existing = bestByID[enriched.id], existing.confidence >= enriched.confidence {
                    continue
                }
                bestByID[enriched.id] = enriched
            }
        }

        return bestByID.values
            .sorted {
                if $0.confidence == $1.confidence {
                    return $0.name < $1.name
                }
                return $0.confidence > $1.confidence
            }
            .prefix(limit)
            .map { $0 }
    }

    func refreshFromPokemonTCGIfNeeded(
        maxPages: Int = 120,
        pageSize: Int = 250,
        allowSeededRefresh: Bool = true
    ) async {
        guard !isRefreshing else { return }
        guard shouldRefreshCache(allowSeededRefresh: allowSeededRefresh) else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let records = try await PokemonTCGIndexClient().downloadIndex(maxPages: maxPages, pageSize: pageSize)
            guard !records.isEmpty else { return }
            update(with: records)
            print("[RareCheck] Pokemon TCG local index refreshed: \(records.count) cards")
        } catch {
            print("[RareCheck] Pokemon TCG local index refresh skipped: \(error.localizedDescription)")
        }
    }

    private func shouldRefreshCache(allowSeededRefresh: Bool) -> Bool {
        if !allowSeededRefresh,
           !(index?.isEmpty ?? true),
           (try? FileManager.default.attributesOfItem(atPath: cacheURL.path)) == nil {
            return false
        }

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
              let modifiedAt = attributes[.modificationDate] as? Date,
              !(index?.isEmpty ?? true) else {
            return true
        }
        return Date().timeIntervalSince(modifiedAt) >= refreshInterval
    }

    private func loadBundledSeed() -> [LocalCardRecord]? {
        let bundles = [Bundle.main, Bundle(for: LocalCardIndex.self)] + Bundle.allBundles
        for bundle in bundles {
            guard let url = bundle.url(forResource: seedResourceName, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let records = try? JSONDecoder().decode([LocalCardRecord].self, from: data) else {
                continue
            }
            return records
        }
        return nil
    }

    private static func normalizedSearchText(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^a-zA-Z0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func baseRescueConfidence(candidate: String, resultName: String) -> Double {
        guard !candidate.isEmpty, !resultName.isEmpty else { return 0 }
        if candidate == resultName { return 0.68 }
        if resultName.hasPrefix(candidate) || candidate.hasPrefix(resultName) { return 0.54 }
        if resultName.contains(candidate) || candidate.contains(resultName) { return 0.45 }

        let candidateTerms = Set(candidate.split(separator: " ").map(String.init))
        let resultTerms = Set(resultName.split(separator: " ").map(String.init))
        let overlap = candidateTerms.intersection(resultTerms).count
        guard overlap > 0 else { return 0 }
        return min(0.36 + Double(overlap) * 0.08, 0.52)
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

private struct PokemonTCGIndexClient {
    private let endpoint = URL(string: "https://api.pokemontcg.io/v2/cards")!

    func downloadIndex(maxPages: Int, pageSize: Int) async throws -> [LocalCardRecord] {
        let boundedPageSize = min(max(pageSize, 1), 250)
        let boundedPages = min(max(maxPages, 1), 120)
        var records: [LocalCardRecord] = []
        var totalCount: Int?

        for page in 1...boundedPages {
            var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "pageSize", value: "\(boundedPageSize)"),
                URLQueryItem(name: "select", value: "id,name,set,number,rarity,images,tcgplayer")
            ]

            let (data, response) = try await URLSession.shared.data(from: components.url!)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw APIError.invalidResponse
            }

            let decoded = try JSONDecoder().decode(PokemonTCGCardPage.self, from: data)
            totalCount = decoded.totalCount
            records += decoded.data.compactMap(\.localRecord)

            if decoded.data.count < boundedPageSize { break }
            if let totalCount, records.count >= totalCount { break }
        }

        return records
    }
}

private struct PokemonTCGCardPage: Decodable {
    let data: [PokemonTCGCard]
    let totalCount: Int?
}

private struct PokemonTCGCard: Decodable {
    let id: String
    let name: String
    let set: PokemonTCGSet?
    let number: String?
    let rarity: String?
    let images: PokemonTCGImages?
    let tcgplayer: PokemonTCGPlayer?

    var localRecord: LocalCardRecord? {
        LocalCardRecord(
            id: id,
            name: name,
            setName: set?.name ?? "",
            setCode: set?.id ?? "",
            collectorNumber: number ?? "",
            rarity: rarity ?? "",
            imageURL: images?.small ?? images?.large ?? "",
            pHash: nil,
            lastKnownPrice: tcgplayer?.preferredPrice
        )
    }
}

private struct PokemonTCGSet: Decodable {
    let id: String
    let name: String
}

private struct PokemonTCGImages: Decodable {
    let small: String?
    let large: String?
}

private struct PokemonTCGPlayer: Decodable {
    let prices: [String: PokemonTCGPrice]?

    var preferredPrice: PriceData? {
        let preferred = ["holofoil", "normal", "reverseHolofoil", "1stEditionHolofoil", "unlimitedHolofoil"]
            .compactMap { prices?[$0] }
            .first
        guard let preferred else { return nil }
        return PriceData(
            low: preferred.low ?? 0,
            mid: preferred.mid ?? 0,
            high: preferred.high ?? 0,
            market: preferred.market ?? preferred.mid ?? 0,
            currency: "USD",
            updatedAt: Date()
        )
    }
}

private struct PokemonTCGPrice: Decodable {
    let low: Double?
    let mid: Double?
    let high: Double?
    let market: Double?
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
    @Published var isFramed = false

    @Published var shouldAutoCapture = false

    private let identificationService = CardIdentificationService.shared
    private let persistenceController = PersistenceController.shared

    private var frameThrottle = 0
    private var stableFrameCount = 0
    private var lastDetectedFrame: DetectedCardFrame?
    private var autoCaptureArmed = true
    private let analysisThrottle = 2
    private let lockThreshold = 2

    func analyzeFrame(_ buffer: CVPixelBuffer) {
        frameThrottle += 1
        guard frameThrottle % analysisThrottle == 0 else { return }
        let detectedFrame = CardDetector.shared.detectFrame(in: buffer)
        Task { @MainActor in
            self.applyDetection(detectedFrame)
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

    func saveCard(_ card: CardMatch) -> PersistenceController.SaveOutcome {
        persistenceController.saveCard(card)
    }

    func prepareCapturedImage(_ image: UIImage) async -> UIImage {
        await CardDetector.shared.detectAndCrop(from: image) ?? image.rareCheckNormalizedUp()
    }

    func markCaptureStarted() {
        shouldAutoCapture = false
        autoCaptureArmed = false
    }

    func markCaptureFinished() {
        if !isLocked {
            autoCaptureArmed = true
        }
    }

    func applyDetection(_ detectedFrame: DetectedCardFrame?) {
        isDetecting = detectedFrame != nil

        guard let detectedFrame else {
            isFramed = false
            stableFrameCount = 0
            lastDetectedFrame = nil
            isLocked = false
            lockProgress = 0
            autoCaptureArmed = true
            shouldAutoCapture = false
            return
        }

        isFramed = detectedFrame.isUsablyFramed
        guard isFramed else {
            stableFrameCount = 0
            lastDetectedFrame = nil
            isLocked = false
            lockProgress = 0
            shouldAutoCapture = false
            return
        }

        if let lastDetectedFrame, detectedFrame.isStable(comparedTo: lastDetectedFrame) {
            stableFrameCount = min(stableFrameCount + 1, lockThreshold)
        } else {
            stableFrameCount = 1
        }

        lastDetectedFrame = detectedFrame
        isLocked = stableFrameCount >= lockThreshold
        lockProgress = Double(stableFrameCount) / Double(lockThreshold)

        if !isLocked {
            shouldAutoCapture = false
            return
        }

        guard autoCaptureArmed, !isProcessing else { return }
        shouldAutoCapture = true
    }
}

extension IdentificationResult: Identifiable {
    var id: String { "\(processingTimeMs)-\(matches.first?.id ?? "unknown")" }
}

enum CardIdentificationError: LocalizedError {
    case noCardDetected
    case noReadableCardText
    case noConfidentPokemonMatch([String])

    var errorDescription: String? {
        switch self {
        case .noCardDetected:
            return "No trading card was captured. Align one card inside the frame until the border turns green, then scan again."
        case .noReadableCardText:
            return "I found a card shape, but couldn't read a Pokemon card name. Move closer, reduce glare, and hold steady until READY."
        case .noConfidentPokemonMatch(let candidates):
            let names = candidates
                .compactMap(Self.displayableCandidate)
                .prefix(3)
                .joined(separator: ", ")
            if names.isEmpty {
                return "I found a card shape, but couldn't read a confident Pokemon card name. Move closer, reduce glare, and center the card name."
            }
            return "No confident Pokemon database match found for: \(names). Try moving closer, reducing glare, and centering the card name."
        }
    }

    private static func displayableCandidate(_ value: String) -> String? {
        let cleaned = value
            .replacingOccurrences(of: #"[^A-Za-z0-9 '.:-]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleaned.count >= 3, cleaned.count <= 40 else { return nil }
        guard cleaned.range(of: #"^[0-9 .:-]|^\d+$|\s\d+\b"#, options: .regularExpression) == nil else { return nil }
        guard cleaned.filter(\.isLetter).count >= 3 else { return nil }
        return cleaned
    }
}

private extension UIImage {
    func rareCheckNormalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
