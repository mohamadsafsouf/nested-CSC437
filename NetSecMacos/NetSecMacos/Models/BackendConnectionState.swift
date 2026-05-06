import SwiftUI

enum BackendConnectionState: Equatable {
    case unchecked
    case checking
    case connected(service: String)
    case disconnected(message: String)

    var title: String {
        switch self {
        case .unchecked:
            return "Cloud status"
        case .checking:
            return "Checking"
        case .connected:
            return "Protected"
        case .disconnected:
            return "Offline"
        }
    }

    var detail: String {
        switch self {
        case .unchecked:
            return "Cloud sync will be checked when the app starts."
        case .checking:
            return "Verifying secure cloud sync."
        case .connected:
            return "Secure cloud sync is available."
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
