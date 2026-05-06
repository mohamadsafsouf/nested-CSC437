import Foundation
import os

final class EventAPIClient {
    private let baseURL: URL
    private let urlSession: URLSession
    private let logger = Logger(subsystem: "CamGuardMac", category: "EventAPI")
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL = AppConfiguration.backendBaseURL, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder.dateDecodingStrategy = .iso8601
        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder.dateEncodingStrategy = .iso8601
    }

    func saveCameraEvent(_ event: CameraEventSyncRequest, accessToken: String) async throws -> CameraEventSyncResponse {
        let bodyData = try encoder.encode(event)
        var request = URLRequest(url: baseURL.appending(path: "/events/camera"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            logger.warning("Event save failed with status \(httpResponse.statusCode, privacy: .public)")
            throw AuthAPIError.serverMessage("Camera activity could not be saved.")
        }
        return try decoder.decode(CameraEventSyncResponse.self, from: data)
    }

    func fetchCameraEvents(accessToken: String, limit: Int = 50) async throws -> CameraEventHistoryResponse {
        var components = URLComponents(url: baseURL.appending(path: "/events/camera"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        guard let url = components?.url else {
            throw AuthAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            logger.warning("Event fetch failed with status \(httpResponse.statusCode, privacy: .public)")
            throw AuthAPIError.serverMessage("Camera activity could not be loaded.")
        }
        return try decoder.decode(CameraEventHistoryResponse.self, from: data)
    }
}

struct CameraEventSyncRequest: Encodable {
    let clientEventId: UUID
    let deviceId: UUID
    let eventType: String
    let cameraStatus: String
    let permissionStatus: String
    let occurredAt: Date
    let collectedAt: Date
    let application: CameraEventApplication
    let durationSeconds: Double?
    let activationCountRecentWindow: Int
    let isBackgroundAccess: Bool
    let isRepeatedShortActivation: Bool
    let networkUploadAfterCamera: Bool
    let observedWebsiteUrl: String?
    let observedWebsiteHost: String?
    let notes: String?
}

struct CameraEventApplication: Encodable {
    let displayName: String
    let bundleIdentifier: String?
    let processId: Int?
    let signingTeamId: String?
    let isTrusted: Bool
    let isKnown: Bool
}

struct CameraEventSyncResponse: Decodable {
    let id: UUID
    let clientEventId: UUID
    let saved: Bool
    let score: CameraEventScore
}

struct CameraEventScore: Decodable {
    let anomalyScore: Double
    let contextualScore: Double
    let threatProbability: Double
    let threatLevel: String
}

struct CameraEventHistoryResponse: Decodable {
    let events: [CameraEventHistoryItem]
}

struct CameraEventHistoryItem: Decodable {
    let id: UUID
    let clientEventId: UUID
    let occurredAt: Date
    let cameraStatus: String
    let notes: String?
    let applicationDisplayName: String?
    let observedProcessId: Int?
    let observedBundleIdentifier: String?
    let observedWebsiteUrl: String?
    let observedWebsiteHost: String?
    let score: CameraEventScore?
}
