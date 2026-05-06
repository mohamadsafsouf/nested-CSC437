import Foundation
import os

enum AuthAPIError: LocalizedError {
    case invalidResponse
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The CamGuard server returned an invalid response."
        case .serverMessage(let message):
            return message
        }
    }
}

final class AuthAPIClient {
    let baseURL: URL
    private let urlSession: URLSession
    private let logger = Logger(subsystem: "CamGuardiOS", category: "AuthAPI")
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL = AppConfiguration.backendBaseURL, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    func signUp(email: String, password: String, displayName: String) async throws -> AuthResponseDTO {
        try await send(
            path: "/auth/sign-up",
            method: "POST",
            body: SignUpRequestDTO(email: email, password: password, displayName: displayName),
            responseType: AuthResponseDTO.self
        )
    }

    func signIn(email: String, password: String) async throws -> AuthResponseDTO {
        try await send(
            path: "/auth/sign-in",
            method: "POST",
            body: SignInRequestDTO(email: email, password: password),
            responseType: AuthResponseDTO.self
        )
    }

    func signOut(accessToken: String) async throws {
        let _: StatusResponseDTO = try await send(
            path: "/auth/sign-out",
            method: "POST",
            body: SignOutRequestDTO(accessToken: accessToken),
            responseType: StatusResponseDTO.self
        )
    }

    func resendConfirmation(email: String) async throws {
        let _: StatusResponseDTO = try await send(
            path: "/auth/resend-confirmation",
            method: "POST",
            body: ResendConfirmationRequestDTO(email: email),
            responseType: StatusResponseDTO.self
        )
    }

    func currentUser(accessToken: String) async throws -> AuthUserDTO {
        try await send(
            path: "/auth/me",
            method: "GET",
            authorization: "Bearer \(accessToken)",
            responseType: AuthUserDTO.self
        )
    }

    func healthCheck() async throws -> HealthResponseDTO {
        try await send(path: "/health", method: "GET", responseType: HealthResponseDTO.self)
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        authorization: String? = nil,
        responseType: Response.Type
    ) async throws -> Response {
        try await send(path: path, method: method, bodyData: nil, authorization: authorization, responseType: responseType)
    }

    private func send<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body,
        authorization: String? = nil,
        responseType: Response.Type
    ) async throws -> Response {
        try await send(
            path: path,
            method: method,
            bodyData: try encoder.encode(body),
            authorization: authorization,
            responseType: responseType
        )
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        bodyData: Data?,
        authorization: String?,
        responseType: Response.Type
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authorization {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = bodyData

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = decodeErrorMessage(from: data) ?? "Request failed with status \(httpResponse.statusCode)."
            logger.warning("Auth API rejected request with status \(httpResponse.statusCode, privacy: .public)")
            throw AuthAPIError.serverMessage(message)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            logger.error("Failed to decode Auth API response: \(error.localizedDescription, privacy: .public)")
            throw AuthAPIError.invalidResponse
        }
    }

    private func decodeErrorMessage(from data: Data) -> String? {
        guard let error = try? decoder.decode(ErrorResponseDTO.self, from: data) else {
            return nil
        }
        return error.detail
    }
}

final class DeviceAPIClient {
    private let baseURL: URL
    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL = AppConfiguration.backendBaseURL, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    func registerDevice(_ metadata: LocalDeviceMetadata, accessToken: String) async throws -> RegisteredDevice {
        try await send(
            path: "/devices/register",
            method: "POST",
            body: metadata,
            accessToken: accessToken,
            responseType: RegisteredDevice.self
        )
    }

    func listDevices(accessToken: String) async throws -> [RegisteredDevice] {
        try await send(
            path: "/devices",
            method: "GET",
            bodyData: nil,
            accessToken: accessToken,
            responseType: [RegisteredDevice].self
        )
    }

    private func send<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body,
        accessToken: String,
        responseType: Response.Type
    ) async throws -> Response {
        try await send(
            path: path,
            method: method,
            bodyData: try encoder.encode(body),
            accessToken: accessToken,
            responseType: responseType
        )
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        bodyData: Data?,
        accessToken: String,
        responseType: Response.Type
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AuthAPIError.serverMessage("Device sync failed. Please try again.")
        }

        return try decoder.decode(Response.self, from: data)
    }
}

final class EventAPIClient {
    private let baseURL: URL
    private let urlSession: URLSession
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
        var request = URLRequest(url: baseURL.appending(path: "/events/camera"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(event)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
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
            throw AuthAPIError.serverMessage("Camera activity could not be loaded.")
        }
        return try decoder.decode(CameraEventHistoryResponse.self, from: data)
    }
}

struct SignUpRequestDTO: Encodable {
    let email: String
    let password: String
    let displayName: String
}

struct SignInRequestDTO: Encodable {
    let email: String
    let password: String
}

struct SignOutRequestDTO: Encodable {
    let accessToken: String
}

struct ResendConfirmationRequestDTO: Encodable {
    let email: String
}

struct AuthResponseDTO: Decodable {
    let user: AuthUserDTO
    let session: AuthSessionDTO?
}

struct AuthUserDTO: Decodable {
    let id: UUID
    let email: String?
    let displayName: String?
}

struct AuthSessionDTO: Decodable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int?
    let expiresAt: Int?
}

struct StatusResponseDTO: Decodable {
    let status: String
}

struct HealthResponseDTO: Decodable {
    let status: String
    let service: String
}

struct ErrorResponseDTO: Decodable {
    let detail: String?
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
    let sourceDeviceId: UUID?
    let sourceDeviceName: String?
    let sourceDeviceType: String?
    let sourceDeviceOs: String?
    let protectionAction: String?
    let protectionResult: String?
    let protectionConfidence: String?
    let score: CameraEventScore?
}
