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
}

struct PriceHistoryPoint: Codable, Identifiable {
    var id: String { date }
    let date: String
    let market: Double
}

// MARK: - API Request / Response Wrappers

struct CardIdentifyRequest: Codable {
    let image: String       // base64-encoded JPEG
    let userId: String?
    let ocrHints: CardIdentifyOCRHints?
}

struct CardIdentifyResponse: Codable {
    let matches: [CardMatch]
    let processingTimeMs: Int
}

struct CardIdentifyOCRHints: Codable {
    let name: String?
    let collectorNumber: String?
    let setCode: String?
    let rawText: String?
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
