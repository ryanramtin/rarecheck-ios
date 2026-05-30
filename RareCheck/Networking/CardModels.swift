import Foundation

// MARK: - Card Domain Models

struct CardMatch: Codable, Identifiable, Hashable {
    let id: String          // cardId e.g. "xy1-1"
    let name: String
    let setName: String
    let setCode: String
    let collectorNumber: String
    let rarity: String
    let imageURL: String
    let confidence: Double  // 0.0 – 1.0
    let price: PriceData

    var confidencePercent: Int { Int(confidence * 100) }
    var canSaveToCollection: Bool {
        persistenceReady != nil
    }

    var persistenceReady: CardMatch? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let trimmedSetCode = setCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCollectorNumber = collectorNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedImageURL = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasDisplayMetadata = !trimmedImageURL.isEmpty || (!trimmedSetCode.isEmpty && !trimmedCollectorNumber.isEmpty)
        guard hasDisplayMetadata else { return nil }

        let resolvedID: String
        if !trimmedID.isEmpty {
            resolvedID = trimmedID
        } else if !trimmedSetCode.isEmpty, !trimmedCollectorNumber.isEmpty {
            resolvedID = "\(trimmedSetCode)-\(trimmedCollectorNumber)"
        } else {
            resolvedID = trimmedName
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: "-")
        }

        return CardMatch(
            id: resolvedID,
            name: trimmedName,
            setName: setName.trimmingCharacters(in: .whitespacesAndNewlines),
            setCode: trimmedSetCode,
            collectorNumber: trimmedCollectorNumber,
            rarity: rarity.trimmingCharacters(in: .whitespacesAndNewlines),
            imageURL: trimmedImageURL,
            confidence: confidence,
            price: price
        )
    }

    var preferredDisplayImageURL: URL? {
        URL(string: preferredCollectionImageURL)
    }
    var preferredCollectionImageURL: String {
        let cleaned = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.contains("images.pokemontcg.io") {
            return cleaned
        }

        let setComponent = setCode.isEmpty ? id.split(separator: "-").first.map(String.init) ?? "" : setCode
        let numberComponent = collectorNumber.isEmpty ? id.split(separator: "-").dropFirst().first.map(String.init) ?? "" : collectorNumber
        if !setComponent.isEmpty, !numberComponent.isEmpty {
            return "https://images.pokemontcg.io/\(setComponent)/\(numberComponent)_hires.png"
        }

        return cleaned
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case setName
        case setCode
        case collectorNumber
        case rarity
        case imageURL = "imageUrl"
        case confidence
        case price
    }

    init(
        id: String,
        name: String,
        setName: String,
        setCode: String,
        collectorNumber: String,
        rarity: String,
        imageURL: String,
        confidence: Double,
        price: PriceData
    ) {
        self.id = id
        self.name = name
        self.setName = setName
        self.setCode = setCode
        self.collectorNumber = collectorNumber
        self.rarity = rarity
        self.imageURL = imageURL
        self.confidence = confidence
        self.price = price
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        setName = try container.decodeIfPresent(String.self, forKey: .setName) ?? ""
        setCode = try container.decodeIfPresent(String.self, forKey: .setCode) ?? ""
        collectorNumber = try container.decodeIfPresent(String.self, forKey: .collectorNumber) ?? ""
        rarity = try container.decodeIfPresent(String.self, forKey: .rarity) ?? ""
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL) ?? ""
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
        price = try container.decodeIfPresent(PriceData.self, forKey: .price) ?? .zero
    }
}

struct PriceData: Codable, Hashable {
    let low: Double
    let mid: Double
    let high: Double
    let market: Double
    let currency: String
    let updatedAt: Date

    var formattedMarket: String {
        "$\(String(format: "%.2f", market))"
    }
    var formattedRange: String {
        "$\(String(format: "%.2f", low)) – $\(String(format: "%.2f", high))"
    }

    init(low: Double, mid: Double, high: Double, market: Double, currency: String, updatedAt: Date) {
        self.low = low
        self.mid = mid
        self.high = high
        self.market = market
        self.currency = currency
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        low = try container.decodeIfPresent(Double.self, forKey: .low) ?? 0
        mid = try container.decodeIfPresent(Double.self, forKey: .mid) ?? 0
        high = try container.decodeIfPresent(Double.self, forKey: .high) ?? 0
        market = try container.decodeIfPresent(Double.self, forKey: .market) ?? 0
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "USD"

        if let raw = try container.decodeIfPresent(String.self, forKey: .updatedAt),
                  let parsed = Self.iso8601WithFractions.date(from: raw) ?? Self.iso8601.date(from: raw) {
            updatedAt = parsed
        } else if let date = try? container.decodeIfPresent(Date.self, forKey: .updatedAt) {
            updatedAt = date
        } else {
            updatedAt = Date()
        }
    }

    private static let iso8601WithFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601 = ISO8601DateFormatter()
}

struct PriceHistoryPoint: Codable, Identifiable {
    var id: String { date }
    let date: String
    let market: Double
}

// MARK: - API Request / Response Wrappers

struct CardIdentifyRequest: Encodable {
    let image: String       // base64-encoded JPEG
    let userId: String?
    let ocrHints: CardIdentifyOCRHints?
}

struct CardIdentifyResponse: Codable {
    let matches: [CardMatch]
    let processingTimeMs: Int
}

struct CardIdentifyOCRHints: Encodable {
    let name: String?
    let collectorNumber: String?
    let setCode: String?
    let rawText: String?

    enum CodingKeys: String, CodingKey {
        case name
        case collectorNumber
        case setCode
        case rawText
    }
}

struct CardDetailResponse: Codable {
    let card: CardMatch
}

struct PriceHistoryResponse: Codable {
    let history: [PriceHistoryPoint]
}

// MARK: - OCR Extraction Result

struct OCRCardInfo {
    let name: String?
    let collectorNumber: String?
    let setCode: String?
    let rawText: String
}

// MARK: - Identification Result

struct IdentificationResult {
    let matches: [CardMatch]
    let source: Source
    let processingTimeMs: Int

    enum Source { case local, api }
}
