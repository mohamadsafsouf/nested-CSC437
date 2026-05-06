import Foundation
import SwiftUI

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
            detail: "No active camera session is currently detected.",
            status: .normal
        ),
        MonitoringSnapshot(
            title: "Permission",
            value: "Ready",
            detail: "Camera access is handled with transparent, user-approved permission checks.",
            status: .normal
        ),
        MonitoringSnapshot(
            title: "Network Correlation",
            value: "Ready",
            detail: "Remote endpoint metadata is correlated without collecting camera media.",
            status: .normal
        )
    ]
}
