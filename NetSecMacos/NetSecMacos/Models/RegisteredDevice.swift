import Foundation

struct RegisteredDevice: Codable, Identifiable, Equatable {
    let id: UUID
    let clientDeviceId: String
    let displayName: String
    let deviceTypeKey: String
    let osName: String
    let osVersion: String
    let modelName: String?
    let lastSeenAt: String?

    var subtitle: String {
        "\(osName) \(osVersion)"
    }

    var lastSeenSummary: String {
        guard lastSeenAt != nil else {
            return "Awaiting first sync"
        }
        return "Synced recently"
    }
}

struct LocalDeviceMetadata: Encodable {
    let clientDeviceId: String
    let displayName: String
    let deviceTypeKey: String
    let osName: String
    let osVersion: String
    let modelName: String?
}
