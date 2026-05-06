import Foundation

struct AppUser: Codable, Equatable, Identifiable {
    let id: UUID
    var email: String
    var displayName: String
    var signedInAt: Date

    var initials: String {
        let source = displayName.isEmpty ? email : displayName
        let parts = source
            .split { !$0.isLetter && !$0.isNumber }
            .prefix(2)
        let letters = parts.compactMap { $0.first }
        return letters.isEmpty ? "CG" : letters.map(String.init).joined().uppercased()
    }
}
