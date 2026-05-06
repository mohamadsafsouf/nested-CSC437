import Foundation
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case overview
    case activity
    case devices
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .activity:
            return "Activity"
        case .devices:
            return "Devices"
        case .settings:
            return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            return "shield.lefthalf.filled"
        case .activity:
            return "waveform.path.ecg"
        case .devices:
            return "iphone"
        case .settings:
            return "gearshape"
        }
    }
}

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
        let letters = parts.compactMap(\.first)
        return letters.isEmpty ? "CG" : letters.map(String.init).joined().uppercased()
    }
}

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int?
    let expiresAt: Int?
}

enum BackendConnectionState: Equatable {
    case unchecked
    case checking
    case connected(service: String)
    case disconnected(message: String)

    var title: String {
        switch self {
        case .unchecked:
            return "Health"
        case .checking:
            return "Checking"
        case .connected:
            return "Healthy"
        case .disconnected:
            return "Attention"
        }
    }

    var detail: String {
        switch self {
        case .unchecked:
            return "Service health will be checked when the app starts."
        case .checking:
            return "Checking CamGuard service health."
        case .connected:
            return "CamGuard service is reachable."
        case .disconnected(let message):
            return message
        }
    }

    var color: Color {
        switch self {
        case .unchecked, .checking:
            return AppTheme.ColorToken.warning
        case .connected:
            return AppTheme.ColorToken.accent
        case .disconnected:
            return AppTheme.ColorToken.critical
        }
    }
}

enum MonitoringStatus: String, CaseIterable, Codable, Identifiable {
    case normal
    case suspicious
    case critical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal:
            return "Normal"
        case .suspicious:
            return "Suspicious"
        case .critical:
            return "Critical"
        }
    }

    var color: Color {
        switch self {
        case .normal:
            return AppTheme.ColorToken.accent
        case .suspicious:
            return AppTheme.ColorToken.warning
        case .critical:
            return AppTheme.ColorToken.critical
        }
    }
}

struct MonitoringSnapshot: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String
    let status: MonitoringStatus
}

struct HealthKPI: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String
    let status: MonitoringStatus
}

extension MonitoringSnapshot {
    static let sample: [MonitoringSnapshot] = [
        MonitoringSnapshot(
            title: "Camera Status",
            value: "Idle",
            detail: "No CamGuard in-app camera session is running.",
            status: .normal
        ),
        MonitoringSnapshot(
            title: "Permission",
            value: "Checking",
            detail: "Camera permission status will appear here.",
            status: .normal
        ),
        MonitoringSnapshot(
            title: "Device Sync",
            value: "Pending",
            detail: "This iPhone or iPad will enroll after sign-in.",
            status: .suspicious
        )
    ]
}

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

enum SecurityActivityKind: String, Codable {
    case cameraStatus
    case permissionStatus
    case monitoring
    case privacy

    var icon: String {
        switch self {
        case .cameraStatus:
            return "video"
        case .permissionStatus:
            return "hand.raised"
        case .monitoring:
            return "shield.checkered"
        case .privacy:
            return "lock.shield"
        }
    }
}

struct SecurityActivityEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let occurredAt: Date
    let kind: SecurityActivityKind
    let title: String
    let detail: String
    let status: MonitoringStatus
    let observedApplicationName: String?
    let observedProcessID: Int32?
    let observedBundleIdentifier: String?
    let sourceDeviceName: String?
    let sourceDeviceType: String?
    let sourceDeviceOS: String?
    let actionSummary: String?
    var isSaved: Bool
    var saveError: String?
    var anomalyScore: Double?
    var contextualScore: Double?
    var threatProbability: Double?
    var threatLevel: String?

    init(
        id: UUID = UUID(),
        occurredAt: Date = Date(),
        kind: SecurityActivityKind,
        title: String,
        detail: String,
        status: MonitoringStatus,
        observedApplicationName: String? = nil,
        observedProcessID: Int32? = nil,
        observedBundleIdentifier: String? = nil,
        sourceDeviceName: String? = nil,
        sourceDeviceType: String? = nil,
        sourceDeviceOS: String? = nil,
        actionSummary: String? = nil,
        isSaved: Bool = false,
        saveError: String? = nil,
        anomalyScore: Double? = nil,
        contextualScore: Double? = nil,
        threatProbability: Double? = nil,
        threatLevel: String? = nil
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.kind = kind
        self.title = title
        self.detail = detail
        self.status = status
        self.observedApplicationName = observedApplicationName
        self.observedProcessID = observedProcessID
        self.observedBundleIdentifier = observedBundleIdentifier
        self.sourceDeviceName = sourceDeviceName
        self.sourceDeviceType = sourceDeviceType
        self.sourceDeviceOS = sourceDeviceOS
        self.actionSummary = actionSummary
        self.isSaved = isSaved
        self.saveError = saveError
        self.anomalyScore = anomalyScore
        self.contextualScore = contextualScore
        self.threatProbability = threatProbability
        self.threatLevel = threatLevel
    }

    var timeSummary: String {
        occurredAt.formatted(date: .omitted, time: .shortened)
    }

    var sourceName: String {
        let name = observedApplicationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Unknown Application" : name
    }

    var sourceDeviceSummary: String {
        let name = sourceDeviceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let os = sourceDeviceOS?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty, !os.isEmpty {
            return "\(name) - \(os)"
        }
        if !name.isEmpty {
            return name
        }
        return "Unknown device"
    }
}
