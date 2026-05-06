import Foundation

enum ProtectionAction: String, Codable {
    case none
    case warnOnly
    case closeBrowserTab
    case terminateProcess
    case requestManualReview
    case openPrivacySettings

    var title: String {
        switch self {
        case .none:
            return "No action"
        case .warnOnly:
            return "Warning shown"
        case .closeBrowserTab:
            return "Close website tab"
        case .terminateProcess:
            return "Stop app"
        case .requestManualReview:
            return "Manual review"
        case .openPrivacySettings:
            return "Open Privacy Settings"
        }
    }
}

enum ProtectionConfidence: String, Codable {
    case confirmed
    case likely
    case uncertain

    var title: String { rawValue.capitalized }
}

enum ProtectionReason: String, Codable {
    case threatLevelSuspicious
    case threatLevelCritical
    case untrustedApplication
    case unknownProcessIdentity
    case trustedApplication
    case systemProcessProtected
    case noActionableProcess
    case userConfirmationRequired

    var message: String {
        switch self {
        case .threatLevelSuspicious:
            return "Threat probability exceeded the Suspicious threshold."
        case .threatLevelCritical:
            return "Threat probability exceeded the Critical threshold."
        case .untrustedApplication:
            return "Camera access was attributed to an unknown or untrusted app."
        case .unknownProcessIdentity:
            return "macOS did not fully confirm the camera-owning process."
        case .trustedApplication:
            return "The suspected app is trusted, so automatic termination is blocked."
        case .systemProcessProtected:
            return "The suspected process is protected because it is a system-critical process."
        case .noActionableProcess:
            return "No safe process identifier is available for automatic action."
        case .userConfirmationRequired:
            return "User confirmation is required before stopping this app."
        }
    }
}

struct ProcessInfoModel: Codable, Equatable {
    let processID: Int32
    let appName: String
    let bundleIdentifier: String?
    let identificationReason: String
    let isTrusted: Bool
    let isSystemCritical: Bool
    let isCamGuard: Bool
}

struct ProtectionDecision: Codable, Equatable {
    let eventID: UUID
    let action: ProtectionAction
    let confidence: ProtectionConfidence
    let suspectedProcess: ProcessInfoModel?
    let reasons: [ProtectionReason]
    let requiresConfirmation: Bool
    let explanation: String

    var canStopApp: Bool {
        action == .terminateProcess && suspectedProcess != nil
    }

    var primaryButtonTitle: String {
        switch action {
        case .closeBrowserTab:
            return "Close Website Tab"
        case .terminateProcess:
            return confidence == .confirmed ? "Stop App" : "Review & Stop"
        case .openPrivacySettings, .requestManualReview:
            return "Open Privacy Settings"
        default:
            return action.title
        }
    }
}

struct ProtectionResult: Codable, Equatable {
    let eventID: UUID
    let action: ProtectionAction
    let success: Bool
    let status: String
    let detail: String
    let confidence: ProtectionConfidence
    let processID: Int32?
    let appName: String?
    let timestamp: Date
    let reportPath: String?

    static func skipped(eventID: UUID, decision: ProtectionDecision, status: String) -> ProtectionResult {
        ProtectionResult(
            eventID: eventID,
            action: decision.action,
            success: false,
            status: status,
            detail: decision.explanation,
            confidence: decision.confidence,
            processID: decision.suspectedProcess?.processID,
            appName: decision.suspectedProcess?.appName,
            timestamp: Date(),
            reportPath: nil
        )
    }
}
