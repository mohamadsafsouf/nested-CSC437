import Foundation
import UIKit

@MainActor
final class SecurityReportGenerator {
    func exportActivityReport(
        event: SecurityActivityEvent,
        deviceName: String,
        backendState: BackendConnectionState,
        permissionState: CameraPermissionState,
        payload: CameraEventSyncRequest?
    ) async -> URL? {
        let html = reportHTML(
            title: "Camera Security Report",
            eyebrow: event.status.title.uppercased(),
            summary: event.detail,
            status: event.status,
            rows: [
                ("Event", event.title),
                ("Event ID", event.id.uuidString),
                ("Device", deviceName),
                ("Source Device", event.sourceDeviceSummary),
                ("Time", event.occurredAt.formatted(date: .abbreviated, time: .standard)),
                ("Source Name", event.sourceName),
                ("Bundle", event.observedBundleIdentifier ?? "Unavailable"),
                ("Action Taken", event.actionSummary ?? "Recorded only"),
                ("Permission", permissionState.title),
                ("Backend Health", backendState.reportTitle),
                ("Threat Level", event.threatLevel ?? event.status.title),
                ("Threat Probability", event.threatProbability.map { "\(Int($0 * 100))% (\(String(format: "%.6f", $0)))" } ?? "Unavailable"),
                ("Anomaly Score", event.anomalyScore.map { String(format: "%.6f", $0) } ?? "Unavailable"),
                ("Context Score", event.contextualScore.map { String(format: "%.6f", $0) } ?? "Unavailable"),
                ("Weighted Anomaly", event.weightedAnomalyContribution),
                ("Weighted Context", event.weightedContextContribution),
                ("Sigmoid Input", event.sigmoidInput),
                ("Probability Check", event.probabilityRecalculation),
                ("Report Completeness", payload == nil ? "Backend score fields available; original sync payload unavailable for older events." : "Backend score fields and original sync payload are included.")
            ],
            payloadRows: payloadRows(payload: payload, permissionState: permissionState),
            formulaRows: tcbadFormulaRows,
            timeline: [
                "\(event.occurredAt.formatted(date: .abbreviated, time: .standard)) - \(event.title)",
                "\(event.isSaved ? "Saved by backend" : "Local event awaiting backend save") - \(event.saveError ?? "No save error")",
                "\(Date().formatted(date: .abbreviated, time: .standard)) - Report generated"
            ],
            recommendation: recommendation(for: event)
        )

        return writePDF(html: html, filenamePrefix: "CamGuard_Activity_Report")
    }

    func exportHealthReport(
        user: AppUser?,
        device: RegisteredDevice?,
        devices: [RegisteredDevice],
        snapshots: [MonitoringSnapshot],
        backendState: BackendConnectionState,
        permissionState: CameraPermissionState
    ) async -> URL? {
        let unhealthySnapshots = snapshots.filter { $0.status != .normal }
        let status: MonitoringStatus = unhealthySnapshots.isEmpty && device != nil && backendState.isHealthy ? .normal : .suspicious
        let summary = status == .normal
            ? "CamGuard reports this iOS device as healthy. Permission, device enrollment, and backend reachability are in a good state."
            : "CamGuard found one or more items that need attention. Review the details below before relying on protection reporting."

        let rows = [
            ("User", user?.email ?? "Unknown"),
            ("Current Device", device?.displayName ?? "Not enrolled"),
            ("Known Devices", "\(devices.count)"),
            ("Permission", permissionState.title),
            ("Backend Health", backendState.reportTitle)
        ] + snapshots.map { ($0.title, "\($0.value) - \($0.detail)") }

        return writePDF(
            html: reportHTML(
                title: "Device Health Report",
                eyebrow: status.title.uppercased(),
                summary: summary,
                status: status,
                rows: rows,
                payloadRows: healthPayloadRows(devices: devices, permissionState: permissionState),
                formulaRows: tcbadFormulaRows,
                timeline: ["\(Date().formatted(date: .abbreviated, time: .standard)) - Health report generated"],
                recommendation: status == .normal
                    ? "Keep CamGuard signed in and run the in-app camera safety test after major iOS updates."
                    : "Refresh health, verify camera permission, and confirm this device is enrolled."
            ),
            filenamePrefix: "CamGuard_Health_Report"
        )
    }

    private func reportHTML(
        title: String,
        eyebrow: String,
        summary: String,
        status: MonitoringStatus,
        rows: [(String, String)],
        payloadRows: [(String, String)],
        formulaRows: [(String, String)],
        timeline: [String],
        recommendation: String
    ) -> String {
        let accent = status.hexColor
        let rowHTML = rows.map { key, value in
            """
            <tr>
              <th>\(key.escapedHTML)</th>
              <td>\(value.escapedHTML)</td>
            </tr>
            """
        }.joined()
        let payloadHTML = payloadRows.map { key, value in
            """
            <tr>
              <th>\(key.escapedHTML)</th>
              <td>\(value.escapedHTML)</td>
            </tr>
            """
        }.joined()
        let formulaHTML = formulaRows.map { key, value in
            """
            <tr>
              <th>\(key.escapedHTML)</th>
              <td><code>\(value.escapedHTML)</code></td>
            </tr>
            """
        }.joined()
        let timelineHTML = timeline.map { "<li>\($0.escapedHTML)</li>" }.joined()

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            @page { size: A4; margin: 0; }
            * { box-sizing: border-box; }
            body {
              margin: 0;
              color: #e5eefc;
              background: #020617;
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", sans-serif;
            }
            .page {
              min-height: 1123px;
              padding: 48px;
              background:
                radial-gradient(circle at 15% 10%, rgba(34,197,94,0.25), transparent 28%),
                radial-gradient(circle at 90% 0%, rgba(14,165,233,0.20), transparent 30%),
                linear-gradient(135deg, #020617 0%, #0f172a 55%, #111827 100%);
            }
            .hero {
              border: 1px solid rgba(255,255,255,0.12);
              border-radius: 32px;
              padding: 34px;
              background: rgba(15, 23, 42, 0.84);
              box-shadow: 0 28px 80px rgba(0,0,0,0.35);
            }
            .brand {
              display: flex;
              justify-content: space-between;
              align-items: center;
              margin-bottom: 38px;
            }
            .logo {
              display: inline-flex;
              align-items: center;
              gap: 12px;
              font-weight: 800;
              letter-spacing: -0.03em;
              font-size: 24px;
            }
            .mark {
              width: 38px;
              height: 38px;
              border-radius: 13px;
              background: \(accent);
              box-shadow: 0 0 24px \(accent);
            }
            .eyebrow {
              color: \(accent);
              font-size: 13px;
              font-weight: 800;
              letter-spacing: 0.18em;
            }
            h1 {
              margin: 0;
              font-size: 54px;
              line-height: 0.95;
              letter-spacing: -0.06em;
            }
            .summary {
              max-width: 640px;
              margin: 22px 0 0;
              color: #a8b3c7;
              font-size: 18px;
              line-height: 1.55;
            }
            .grid {
              display: grid;
              grid-template-columns: 1.2fr 0.8fr;
              gap: 22px;
              margin-top: 26px;
            }
            .card {
              border: 1px solid rgba(255,255,255,0.10);
              border-radius: 24px;
              padding: 24px;
              background: rgba(30,41,59,0.72);
            }
            h2 {
              margin: 0 0 16px;
              font-size: 20px;
              letter-spacing: -0.02em;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              font-size: 13px;
            }
            th, td {
              text-align: left;
              vertical-align: top;
              padding: 11px 0;
              border-bottom: 1px solid rgba(255,255,255,0.08);
            }
            th {
              width: 34%;
              color: #7dd3fc;
              font-weight: 700;
            }
            td {
              color: #e5eefc;
              line-height: 1.4;
            }
            code {
              color: #bbf7d0;
              font-family: "SF Mono", ui-monospace, Menlo, monospace;
              font-size: 11px;
              line-height: 1.45;
              white-space: pre-wrap;
            }
            ul {
              margin: 0;
              padding-left: 18px;
              color: #cbd5e1;
              line-height: 1.65;
            }
            .footer {
              display: flex;
              justify-content: space-between;
              gap: 18px;
              margin-top: 26px;
              color: #94a3b8;
              font-size: 12px;
            }
            .wide {
              margin-top: 22px;
            }
            .badge {
              display: inline-flex;
              padding: 8px 12px;
              border-radius: 999px;
              color: #020617;
              background: \(accent);
              font-weight: 800;
            }
          </style>
        </head>
        <body>
          <main class="page">
            <section class="hero">
              <div class="brand">
                <div class="logo"><span class="mark"></span>CamGuard</div>
                <div class="eyebrow">\(eyebrow.escapedHTML)</div>
              </div>
              <h1>\(title.escapedHTML)</h1>
              <p class="summary">\(summary.escapedHTML)</p>
              <div style="margin-top: 22px;"><span class="badge">\(status.title.escapedHTML)</span></div>
            </section>

            <section class="grid">
              <div class="card">
                <h2>Evidence</h2>
                <table>\(rowHTML)</table>
              </div>
              <div class="card">
                <h2>Timeline</h2>
                <ul>\(timelineHTML)</ul>
                <h2 style="margin-top: 26px;">Recommendation</h2>
                <p style="color:#cbd5e1; line-height:1.6;">\(recommendation.escapedHTML)</p>
              </div>
            </section>

            <section class="card wide">
              <h2>TCB-AD Formula and Calculation Details</h2>
              <table>\(formulaHTML)</table>
            </section>

            <section class="card wide">
              <h2>Raw Metadata Payload</h2>
              <table>\(payloadHTML)</table>
            </section>

            <section class="footer">
              <span>Camera media captured: No</span>
              <span>Camera media uploaded: No</span>
              <span>Generated: \(Date().formatted(date: .abbreviated, time: .shortened))</span>
            </section>
          </main>
        </body>
        </html>
        """
    }

    private func writePDF(html: String, filenamePrefix: String) -> URL? {
        let formatter = UIMarkupTextPrintFormatter(markupText: html)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)

        let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        renderer.setValue(page, forKey: "paperRect")
        renderer.setValue(page.insetBy(dx: 0, dy: 0), forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, page, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: 1))
        for pageIndex in 0..<max(renderer.numberOfPages, 1) {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: pageIndex, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(filenamePrefix)_\(timestamp).pdf")

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private var tcbadFormulaRows: [(String, String)] {
        [
            ("Authoritative scorer", "Backend TCB-AD v1. Clients display backend-returned scores when available."),
            ("Feature vector", "x = [access_time_hour, duration_seconds, activation_frequency]"),
            ("Baseline mean", "mu = [13.0, 90.0, 2.0]"),
            ("Inverse covariance", "Sigma^-1 = [[0.028, 0, 0], [0, 0.0004, 0], [0, 0, 0.25]]"),
            ("Delta", "delta = x - mu"),
            ("Mahalanobis anomaly", "anomaly_score = sqrt(max(delta^T * Sigma^-1 * delta, 0))"),
            ("Context score", "contextual_score = 1.4*background_access + 1.3*unknown_or_untrusted + 3.4*network_upload_after_camera + 0.8*permission_changed_recently + 1.2*repeated_short_activation + 1.4*(same_source_recent_count >= 3) + 1.2*(same_source_recent_count >= 3 and same_source_network_upload_count > 0)"),
            ("Threat logit", "z = (0.85 * anomaly_score) + (1.0 * contextual_score) - 4.0"),
            ("Threat probability", "p = sigmoid(z) = 1 / (1 + e^-z)"),
            ("Normal threshold", "0.00 <= p < 0.50"),
            ("Suspicious threshold", "0.50 <= p < 0.85"),
            ("Critical threshold", "0.85 <= p <= 1.00")
        ]
    }

    private func payloadRows(payload: CameraEventSyncRequest?, permissionState: CameraPermissionState) -> [(String, String)] {
        guard let payload else {
            return [
                ("Payload", "Unavailable for this event. The backend score and saved event fields above are still shown."),
                ("Current Permission", permissionState.title)
            ]
        }

        return [
            ("Client Event ID", payload.clientEventId.uuidString),
            ("Device ID", payload.deviceId.uuidString),
            ("Event Type", payload.eventType),
            ("Camera Status", payload.cameraStatus),
            ("Permission Status", payload.permissionStatus),
            ("Occurred At", payload.occurredAt.formatted(date: .complete, time: .complete)),
            ("Collected At", payload.collectedAt.formatted(date: .complete, time: .complete)),
            ("Application Name", payload.application.displayName),
            ("Bundle Identifier", payload.application.bundleIdentifier ?? "Unavailable"),
            ("Process ID", payload.application.processId.map(String.init) ?? "Unavailable on iOS"),
            ("Signing Team ID", payload.application.signingTeamId ?? "Unavailable"),
            ("Trusted Application", payload.application.isTrusted ? "true" : "false"),
            ("Known Application", payload.application.isKnown ? "true" : "false"),
            ("Duration Seconds", payload.durationSeconds.map { String(format: "%.3f", $0) } ?? "Unavailable"),
            ("Activation Count", "\(payload.activationCountRecentWindow)"),
            ("Background Access", payload.isBackgroundAccess ? "true" : "false"),
            ("Repeated Short Activation", payload.isRepeatedShortActivation ? "true" : "false"),
            ("Network Upload After Camera", payload.networkUploadAfterCamera ? "true" : "false"),
            ("Notes", payload.notes ?? "None")
        ]
    }

    private func healthPayloadRows(
        devices: [RegisteredDevice],
        permissionState: CameraPermissionState
    ) -> [(String, String)] {
        [
            ("Camera Permission", permissionState.title),
            ("Registered Device Count", "\(devices.count)"),
            ("Device Registry", devices.map { "\($0.displayName) (\($0.deviceTypeKey), \($0.subtitle))" }.joined(separator: "\n")),
            ("Camera Media Captured", "false"),
            ("Camera Media Uploaded", "false"),
            ("iOS Other-App Monitoring", "false - iOS sandboxing prevents this.")
        ]
    }

    private func recommendation(for event: SecurityActivityEvent) -> String {
        switch event.status {
        case .normal:
            return "No immediate action is required. Keep CamGuard signed in and review permissions after app or iOS updates."
        case .suspicious:
            return "Review whether this camera or permission activity was expected. If not, open iOS Settings and revoke camera permission."
        case .critical:
            return "Treat this as unexpected camera activity until verified. Revoke permission and review account/device health."
        }
    }
}

private extension BackendConnectionState {
    var isHealthy: Bool {
        if case .connected = self {
            return true
        }
        return false
    }

    var reportTitle: String {
        switch self {
        case .connected:
            return "Healthy"
        case .checking:
            return "Checking"
        case .unchecked:
            return "Not checked"
        case .disconnected:
            return "Needs attention"
        }
    }
}

private extension MonitoringStatus {
    var hexColor: String {
        switch self {
        case .normal:
            return "#22c55e"
        case .suspicious:
            return "#f59e0b"
        case .critical:
            return "#ef4444"
        }
    }
}

private extension SecurityActivityEvent {
    var weightedAnomalyContribution: String {
        guard let anomalyScore else {
            return "Unavailable"
        }
        return String(format: "0.85 * %.6f = %.6f", anomalyScore, 0.85 * anomalyScore)
    }

    var weightedContextContribution: String {
        guard let contextualScore else {
            return "Unavailable"
        }
        return String(format: "1.0 * %.6f = %.6f", contextualScore, contextualScore)
    }

    var sigmoidInput: String {
        guard let anomalyScore, let contextualScore else {
            return "Unavailable"
        }
        let value = (0.85 * anomalyScore) + contextualScore - 4.0
        return String(format: "(0.85 * %.6f) + %.6f - 4.0 = %.6f", anomalyScore, contextualScore, value)
    }

    var probabilityRecalculation: String {
        guard let anomalyScore, let contextualScore else {
            return "Unavailable"
        }
        let input = (0.85 * anomalyScore) + contextualScore - 4.0
        let recalculated = 1 / (1 + exp(-input))
        let backend = threatProbability.map { String(format: "%.6f", $0) } ?? "Unavailable"
        return String(format: "sigmoid(%.6f) = %.6f; backend returned %@", input, recalculated, backend)
    }
}

private extension String {
    var escapedHTML: String {
        var escaped = self
        escaped = escaped.replacingOccurrences(of: "&", with: "&amp;")
        escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
        escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
        escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
        escaped = escaped.replacingOccurrences(of: "'", with: "&#39;")
        return escaped
    }
}
