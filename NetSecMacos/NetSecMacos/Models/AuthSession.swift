import Foundation

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int?
    let expiresAt: Int?

    var authorizationHeader: String {
        "\(tokenType.capitalized) \(accessToken)"
    }
}
