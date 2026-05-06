import AppKit
import Foundation
import os

struct BrowserActivityContext: Equatable {
    let browserName: String
    let bundleIdentifier: String?
    let pageTitle: String?
    let url: String?
    let host: String?

    var sourceDisplayName: String {
        guard let host, !host.isEmpty else {
            return browserName
        }
        return host
    }

    var detailSuffix: String {
        guard let host, !host.isEmpty else {
            return ""
        }
        let title = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty {
            return " Active website: \(host) (\(title))."
        }
        return " Active website: \(host)."
    }
}

@MainActor
final class BrowserActivityContextService {
    private let logger = Logger(subsystem: "CamGuardMac", category: "BrowserContext")

    func context(for app: NSRunningApplication?) -> BrowserActivityContext? {
        guard let appName = app?.localizedName,
              let bundleIdentifier = app?.bundleIdentifier,
              isSupportedBrowser(bundleIdentifier: bundleIdentifier, appName: appName) else {
            return nil
        }

        let script = appleScript(for: bundleIdentifier)
        guard let script else {
            return nil
        }

        var error: NSDictionary?
        guard let descriptor = NSAppleScript(source: script)?.executeAndReturnError(&error) else {
            if let error {
                logger.warning("Browser context AppleScript failed: \(String(describing: error), privacy: .public)")
            }
            return BrowserActivityContext(browserName: appName, bundleIdentifier: bundleIdentifier, pageTitle: nil, url: nil, host: nil)
        }

        let payload = descriptor.stringValue ?? ""
        let parts = payload.components(separatedBy: "\u{1F}")
        let url = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = parts.dropFirst().first?.trimmingCharacters(in: .whitespacesAndNewlines)
        return BrowserActivityContext(
            browserName: appName,
            bundleIdentifier: bundleIdentifier,
            pageTitle: title?.isEmpty == true ? nil : title,
            url: url?.isEmpty == true ? nil : url,
            host: host(from: url)
        )
    }

    private func isSupportedBrowser(bundleIdentifier: String, appName: String) -> Bool {
        let normalizedName = appName.lowercased()
        return bundleIdentifier == "com.apple.Safari"
            || bundleIdentifier == "com.google.Chrome"
            || bundleIdentifier == "com.microsoft.edgemac"
            || bundleIdentifier == "company.thebrowser.Browser"
            || normalizedName == "safari"
            || normalizedName == "google chrome"
            || normalizedName == "microsoft edge"
            || normalizedName == "arc"
    }

    private func appleScript(for bundleIdentifier: String) -> String? {
        switch bundleIdentifier {
        case "com.apple.Safari":
            return safariScript()
        case "com.google.Chrome":
            return chromiumScript(applicationName: "Google Chrome")
        case "com.microsoft.edgemac":
            return chromiumScript(applicationName: "Microsoft Edge")
        case "company.thebrowser.Browser":
            return chromiumScript(applicationName: "Arc")
        default:
            return nil
        }
    }

    private func safariScript() -> String {
        """
        tell application "Safari"
            if (count of windows) is 0 then return ""
            -- Prefer a loopback / simulator camera tab even when it is in the background.
            repeat with browserWindow in windows
                repeat with browserTab in tabs of browserWindow
                    set tabURL to URL of browserTab
                    if my isLoopbackOrSimulator(tabURL) then
                        set pageTitle to name of browserTab
                        return tabURL & "\u{1F}" & pageTitle
                    end if
                end repeat
            end repeat
            -- Fall back to the active tab of the front window.
            set pageUrl to URL of current tab of front window
            set pageTitle to name of current tab of front window
            return pageUrl & "\u{1F}" & pageTitle
        end tell

        on isLoopbackOrSimulator(tabURL)
            if tabURL is missing value then return false
            if tabURL contains "://127.0.0.1" then return true
            if tabURL contains "://localhost" then return true
            if tabURL contains "://[::1]" then return true
            if tabURL contains "/camera-upload-test" then return true
            return false
        end isLoopbackOrSimulator
        """
    }

    private func chromiumScript(applicationName: String) -> String {
        """
        tell application "\(applicationName)"
            if (count of windows) is 0 then return ""
            -- Prefer a loopback / simulator camera tab even when it is in the background.
            repeat with browserWindow in windows
                repeat with browserTab in tabs of browserWindow
                    set tabURL to URL of browserTab
                    if my isLoopbackOrSimulator(tabURL) then
                        set pageTitle to title of browserTab
                        return tabURL & "\u{1F}" & pageTitle
                    end if
                end repeat
            end repeat
            -- Fall back to the active tab of the front window.
            set pageUrl to URL of active tab of front window
            set pageTitle to title of active tab of front window
            return pageUrl & "\u{1F}" & pageTitle
        end tell

        on isLoopbackOrSimulator(tabURL)
            if tabURL is missing value then return false
            if tabURL contains "://127.0.0.1" then return true
            if tabURL contains "://localhost" then return true
            if tabURL contains "://[::1]" then return true
            if tabURL contains "/camera-upload-test" then return true
            return false
        end isLoopbackOrSimulator
        """
    }

    private func host(from urlString: String?) -> String? {
        guard let urlString, !urlString.isEmpty else {
            return nil
        }
        let prepared = urlString.contains("://") ? urlString : "https://\(urlString)"
        guard let host = URL(string: prepared)?.host else {
            return nil
        }
        return host.replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
    }
}
