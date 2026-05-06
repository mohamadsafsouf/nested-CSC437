import AppKit
import Foundation
import os
import UniformTypeIdentifiers
import WebKit

@MainActor
final class SecurityReportGenerator: NSObject {
    private let logger = Logger(subsystem: "CamGuardMac", category: "SecurityReport")

    func exportPdfReport(
        event: SecurityActivityEvent,
        decision: ProtectionDecision?,
        result: ProtectionResult?,
        deviceName: String
    ) async -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let defaultName = "CamGuard_Report_\(event.id.uuidString)_\(formatter.string(from: Date())).pdf"

        let panel = NSSavePanel()
        panel.title = "Download CamGuard Security Report"
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        do {
            let html = reportHTML(
                event: event,
                decision: decision,
                result: result,
                deviceName: deviceName
            )
            let data = try await renderPDF(html: html)
            try data.write(to: url, options: .atomic)
            logger.info("Saved security report to \(url.path, privacy: .private)")
            return url
        } catch {
            logger.error("Failed to save security report: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func reportHTML(
        event: SecurityActivityEvent,
        decision: ProtectionDecision?,
        result: ProtectionResult?,
        deviceName: String
    ) -> String {
        let process = decision?.suspectedProcess
        let action = result?.action.title ?? decision?.action.title ?? "Recorded only"
        let actionResult = result?.status ?? "Not run"
        let actionDetail = result?.detail ?? decision?.explanation ?? "No protection action has been taken."
        let sourceName = event.trustSourceName
        let sourceDevice = "\(deviceName) - \(ProcessInfo.processInfo.operatingSystemVersionString)"

        return reportHTML(
            title: "Camera Security Report",
            eyebrow: event.status.title.uppercased(),
            summary: event.detail,
            status: event.status,
            rows: [
                ("Event", event.title),
                ("Event ID", event.id.uuidString),
                ("Device", deviceName),
                ("Source Device", sourceDevice),
                ("Time", event.occurredAt.formatted(date: .abbreviated, time: .standard)),
                ("Source Name", sourceName),
                ("Application", process?.appName ?? event.observedApplicationName ?? "Unknown Application"),
                ("Website Host", event.observedWebsiteHost ?? "Unavailable"),
                ("Website URL", event.observedWebsiteURL ?? "Unavailable"),
                ("Process ID", process?.processID.description ?? event.observedProcessID?.description ?? "Unavailable"),
                ("Bundle", process?.bundleIdentifier ?? event.observedBundleIdentifier ?? "Unavailable"),
                ("Action Taken", "\(action) - \(actionResult)"),
                ("Action Detail", actionDetail),
                ("Threat Level", event.threatLevel ?? event.status.title),
                ("Threat Probability", event.threatProbability.map { "\(Int($0 * 100))% (\(String(format: "%.6f", $0)))" } ?? "Unavailable"),
                ("Anomaly Score", event.anomalyScore.map { String(format: "%.6f", $0) } ?? "Unavailable"),
                ("Context Score", event.contextualScore.map { String(format: "%.6f", $0) } ?? "Unavailable"),
                ("Weighted Anomaly", event.weightedAnomalyContribution),
                ("Weighted Context", event.weightedContextContribution),
                ("Sigmoid Input", event.sigmoidInput),
                ("Probability Check", event.probabilityRecalculation),
                ("Process Identity Confidence", decision?.confidence.title ?? "Uncertain")
            ],
            payloadRows: payloadRows(event: event, decision: decision, result: result, deviceName: deviceName),
            formulaRows: tcbadFormulaRows,
            timeline: [
                "\(event.occurredAt.formatted(date: .abbreviated, time: .standard)) - \(event.title)",
                "\(event.isSaved ? "Saved by backend" : "Local event awaiting backend save") - \(event.saveError ?? "No save error")",
                "\(Date().formatted(date: .abbreviated, time: .standard)) - Report generated"
            ],
            recommendation: recommendation(for: event)
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
        let rowHTML = tableRows(rows, codeValues: false)
        let payloadHTML = tableRows(payloadRows, codeValues: false)
        let formulaHTML = tableRows(formulaRows, codeValues: true)
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
            .wide { margin-top: 22px; }
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

    private func tableRows(_ rows: [(String, String)], codeValues: Bool) -> String {
        rows.map { key, value in
            let valueHTML = codeValues ? "<code>\(value.escapedHTML)</code>" : value.escapedHTML
            return """
            <tr>
              <th>\(key.escapedHTML)</th>
              <td>\(valueHTML)</td>
            </tr>
            """
        }.joined()
    }

    private func renderPDF(html: String) async throws -> Data {
        let renderer = WebPDFRenderer()
        return try await renderer.render(html: html)
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

    private func payloadRows(
        event: SecurityActivityEvent,
        decision: ProtectionDecision?,
        result: ProtectionResult?,
        deviceName: String
    ) -> [(String, String)] {
        [
            ("Client Event ID", event.id.uuidString),
            ("Device", deviceName),
            ("Event Type", event.kind == .permissionStatus ? "permission_change" : "camera_session"),
            ("Camera Status", cameraStatus(for: event)),
            ("Permission Status", "See current macOS camera permission snapshot in dashboard"),
            ("Occurred At", event.occurredAt.formatted(date: .complete, time: .complete)),
            ("Collected At", Date().formatted(date: .complete, time: .complete)),
            ("Application Name", event.observedApplicationName ?? "Unknown Application"),
            ("Website Host", event.observedWebsiteHost ?? "Unavailable"),
            ("Website URL", event.observedWebsiteURL ?? "Unavailable"),
            ("Bundle Identifier", event.observedBundleIdentifier ?? "Unavailable"),
            ("Process ID", event.observedProcessID.map(String.init) ?? "Unavailable"),
            ("Trusted Source", TrustedCameraApplicationPolicy.context(for: event.observedApplicationName, websiteDomain: event.observedWebsiteHost).isTrusted ? "true" : "false"),
            ("Known Source", TrustedCameraApplicationPolicy.context(for: event.observedApplicationName, websiteDomain: event.observedWebsiteHost).isKnown ? "true" : "false"),
            ("Duration Seconds", "Captured in backend score when available"),
            ("Activation Count", "Captured in backend score when available"),
            ("Background Access", "false"),
            ("Repeated Short Activation", event.title.localizedCaseInsensitiveContains("repeated") ? "true" : "false"),
            (
                "Network Upload After Camera",
                event.networkUploadAfterCamera.map { $0 ? "true" : "false" } ?? "not recorded in client"
            ),
            ("Protection Action", result?.action.rawValue ?? decision?.action.rawValue ?? "none"),
            ("Protection Result", result?.status ?? "Not run"),
            ("Notes", event.detail)
        ]
    }

    private func cameraStatus(for event: SecurityActivityEvent) -> String {
        if event.kind == .permissionStatus {
            return "permission_only"
        }
        if event.title.localizedCaseInsensitiveContains("ended") {
            return "ended"
        }
        if event.title.localizedCaseInsensitiveContains("detected") {
            return "started"
        }
        return "unknown"
    }

    private func recommendation(for event: SecurityActivityEvent) -> String {
        switch event.status {
        case .normal:
            return "No immediate action is required. Keep CamGuard signed in and review camera permissions after app or macOS updates."
        case .suspicious:
            return event.isWebsiteAttributed
                ? "Review whether this website camera access was expected. If it is expected, use Trust Website; otherwise close the tab and revoke camera permission."
                : "Review whether this app camera access was expected. If it is expected, use Trust App; otherwise close the app and review Camera Privacy settings."
        case .critical:
            return "Treat this as unexpected camera activity until verified. Stop or close the source and review account/device health."
        }
    }
}

private final class WebPDFRenderer: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Data, Error>?
    private var webView: WKWebView?

    @MainActor
    func render(html: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let configuration = WKWebViewConfiguration()
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 595.2, height: 841.8), configuration: configuration)
            webView.navigationDelegate = self
            self.webView = webView
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)") { [weak self, weak webView] value, _ in
            guard let self, let webView else { return }
            let renderedHeight = (value as? NSNumber)?.doubleValue ?? 841.8
            let configuration = WKPDFConfiguration()
            configuration.rect = CGRect(x: 0, y: 0, width: 595.2, height: max(renderedHeight, 841.8))
            webView.createPDF(configuration: configuration) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let data):
                    self.continuation?.resume(returning: data)
                case .failure(let error):
                    self.continuation?.resume(throwing: error)
                }
                self.continuation = nil
                self.webView = nil
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
        self.webView = nil
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
