import Foundation

// MARK: - API Client

actor APIClient {
    static let shared = APIClient()

    // Set this to your Railway deployment URL in production
    private let baseURL = ProcessInfo.processInfo.environment["API_BASE_URL"]
        ?? "https://rarecheck-api.railway.app"

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // MARK: - Card Identification

    func identifyCard(imageData: Data, userId: String? = nil) async throws -> CardIdentifyResponse {
        let base64 = imageData.base64EncodedString()
        let body = CardIdentifyRequest(image: base64, userId: userId)
        return try await post(path: "/api/cards/identify", body: body)
    }

    // MARK: - Card Detail

    func cardDetail(cardId: String) async throws -> CardDetailResponse {
        return try await get(path: "/api/cards/\(cardId)")
    }

    // MARK: - Price History

    func priceHistory(cardId: String) async throws -> PriceHistoryResponse {
        return try await get(path: "/api/prices/\(cardId)/history")
    }

    // MARK: - Generics

    private func get<T: Decodable>(path: String) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.addJWTIfAvailable()
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func post<Body: Encodable, T: Decodable>(path: String, body: Body) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addJWTIfAvailable()
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.message
            throw APIError.httpError(statusCode: http.statusCode, message: message)
        }
    }
}

// MARK: - JWT Helper

extension URLRequest {
    mutating func addJWTIfAvailable() {
        if let token = KeychainHelper.shared.readJWT() {
            setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL."
        case .invalidResponse: return "Unexpected server response."
        case .httpError(let code, let msg):
            return msg ?? "Server error (HTTP \(code))."
        }
    }
}

private struct APIErrorBody: Decodable { let message: String }

// MARK: - Keychain Helper (minimal)

final class KeychainHelper {
    static let shared = KeychainHelper()
    private let service = "app.rarecheck.jwt"

    func readJWT() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func saveJWT(_ token: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    func deleteJWT() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}
