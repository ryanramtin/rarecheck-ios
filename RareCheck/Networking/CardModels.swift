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
