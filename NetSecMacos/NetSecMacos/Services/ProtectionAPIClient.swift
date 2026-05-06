import Foundation
import os

final class ProtectionAPIClient {
    private let baseURL: URL
    private let urlSession: URLSession
    private let logger = Logger(subsystem: "CamGuardMac", category: "ProtectionAPI")
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL = AppConfiguration.backendBaseURL, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder.dateEncodingStrategy = .iso8601
    }

    func syncProtectionAction(_ request: ProtectionActionSyncRequest, accessToken: String) async throws {
        let bodyData = try encoder.encode(request)
        var urlRequest = URLRequest(url: baseURL.appending(path: "/protection-actions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = bodyData

        let (_, response) = try await urlSession.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            logger.warning("Protection action sync failed with status \(httpResponse.statusCode, privacy: .public)")
            throw AuthAPIError.serverMessage("Protection action could not be synced.")
        }
    }
}

struct ProtectionActionSyncRequest: Encodable {
    let eventId: UUID
    let deviceId: UUID?
    let appName: String
    let processId: Int?
    let action: String
    let result: String
    let confidence: String
    let timestamp: Date
    let reportPath: String?
}
