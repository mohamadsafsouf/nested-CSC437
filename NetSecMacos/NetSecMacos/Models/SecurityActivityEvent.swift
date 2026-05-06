import Foundation
import SwiftUI

enum SecurityActivityKind: String, Codable {
    case cameraStatus
    case permissionStatus
    case monitoring

    var icon: String {
        switch self {
        case .cameraStatus:
            return "video"
        case .permissionStatus:
            return "hand.raised"
        case .monitoring:
            return "shield.checkered"
        }
    }
}

struct SecurityActivityEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let occurredAt: Date
    let kind: SecurityActivityKind
    let title: String
    let detail: String
    var status: MonitoringStatus
    let observedApplicationName: String?
    let observedProcessID: Int32?
    let observedBundleIdentifier: String?
    let observedWebsiteURL: String?
    let observedWebsiteHost: String?
    var isSaved: Bool
    var saveError: String?
    var anomalyScore: Double?
    var contextualScore: Double?
    var threatProbability: Double?
    var threatLevel: String?
    var protectionDecision: ProtectionDecision?
    var protectionResult: ProtectionResult?
    /// Set after sync when `network_upload_after_camera` is sent to the API (or read from a prior save).
    var networkUploadAfterCamera: Bool?

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
        observedWebsiteURL: String? = nil,
        observedWebsiteHost: String? = nil,
        isSaved: Bool = false,
        saveError: String? = nil,
        anomalyScore: Double? = nil,
        contextualScore: Double? = nil,
        threatProbability: Double? = nil,
        threatLevel: String? = nil,
        protectionDecision: ProtectionDecision? = nil,
        protectionResult: ProtectionResult? = nil,
        networkUploadAfterCamera: Bool? = nil
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
        self.observedWebsiteURL = observedWebsiteURL
        self.observedWebsiteHost = observedWebsiteHost
        self.isSaved = isSaved
        self.saveError = saveError
        self.anomalyScore = anomalyScore
        self.contextualScore = contextualScore
        self.threatProbability = threatProbability
        self.threatLevel = threatLevel
        self.protectionDecision = protectionDecision
        self.protectionResult = protectionResult
        self.networkUploadAfterCamera = networkUploadAfterCamera
    }

    var timeSummary: String {
        occurredAt.formatted(date: .omitted, time: .shortened)
    }

    var requiresProtectionControls: Bool {
        status == .suspicious || status == .critical
    }

    var trustSourceName: String {
        observedWebsiteHost ?? observedApplicationName ?? "Unknown Application"
    }

    var isWebsiteAttributed: Bool {
        observedWebsiteHost != nil
    }
}
