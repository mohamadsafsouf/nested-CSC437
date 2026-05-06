import Foundation
import os

enum AuthAPIError: LocalizedError {
    case invalidResponse
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The authentication server returned an invalid response."
        case .serverMessage(let message):
            return message
        }
    }
}

final class AuthAPIClient {
    let baseURL: URL
    private let urlSession: URLSession
    private let logger = Logger(subsystem: "CamGuardMac", category: "AuthAPI")
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
        try await send(
            path: "/health",
            method: "GET",
            responseType: HealthResponseDTO.self
        )
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
        let bodyData = try encoder.encode(body)
        return try await send(path: path, method: method, bodyData: bodyData, authorization: authorization, responseType: responseType)
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        bodyData: Data?,
        authorization: String?,
        responseType: Response.Type
    ) async throws -> Response {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authorization {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = bodyData

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Auth API response was not HTTP.")
            throw AuthAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = decodeErrorMessage(from: data) ?? "Authentication failed with status \(httpResponse.statusCode)."
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
