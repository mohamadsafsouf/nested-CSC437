import Foundation
import os

final class DeviceAPIClient {
    private let baseURL: URL
    private let urlSession: URLSession
    private let logger = Logger(subsystem: "CamGuardMac", category: "DeviceAPI")
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
        let bodyData = try encoder.encode(body)
        return try await send(path: path, method: method, bodyData: bodyData, accessToken: accessToken, responseType: responseType)
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
            logger.warning("Device API rejected request with status \(httpResponse.statusCode, privacy: .public)")
            throw AuthAPIError.serverMessage("Device sync failed. Please try again.")
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            logger.error("Failed to decode Device API response: \(error.localizedDescription, privacy: .public)")
            throw AuthAPIError.invalidResponse
        }
    }
}
