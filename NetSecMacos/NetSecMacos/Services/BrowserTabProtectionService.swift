import AppKit
import Foundation
import os

@MainActor
final class BrowserTabProtectionService {
    private let logger = Logger(subsystem: "CamGuardMac", category: "BrowserTabProtection")

    func closeTab(for event: SecurityActivityEvent, process: ProcessInfoModel) async -> ProtectionResult {
        guard let bundleIdentifier = process.bundleIdentifier,
              let script = closeTabScript(
                bundleIdentifier: bundleIdentifier,
                websiteURL: event.observedWebsiteURL,
                websiteHost: event.observedWebsiteHost
              ) else {
            return ProtectionResult(
                eventID: event.id,
                action: .closeBrowserTab,
                success: false,
                status: "Tab close unavailable",
                detail: "CamGuard does not have a browser tab close script for \(process.appName).",
                confidence: .uncertain,
                processID: process.processID,
                appName: event.trustSourceName,
                timestamp: Date(),
                reportPath: nil
            )
        }

        var error: NSDictionary?
        let descriptor = NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            logger.warning("Browser tab close AppleScript failed: \(String(describing: error), privacy: .public)")
        }

        // AppleScript returns one of: "closed" (we closed it), "absent" (already gone),
        // "still-open" (we tried but the URL is still open), or "" (error).
        let verdict = descriptor?.stringValue ?? ""
        let didClose = verdict == "closed"
        let alreadyGone = verdict == "absent"
        let success = didClose || alreadyGone

        let status: String
        let detail: String
        if didClose {
            status = "Website tab closed"
            detail = "\(event.trustSourceName) was closed in \(process.appName)."
        } else if alreadyGone {
            status = "Tab already closed"
            detail = "\(event.trustSourceName) is no longer open in \(process.appName); no action needed."
        } else {
            status = "Tab not closed — manual review"
            detail = "CamGuard could not close \(event.trustSourceName) in \(process.appName). The host browser will NOT be terminated; please review and close the tab manually."
        }

        return ProtectionResult(
            eventID: event.id,
            action: .closeBrowserTab,
            success: success,
            status: status,
            detail: detail,
            confidence: success ? .confirmed : .uncertain,
            processID: process.processID,
            appName: event.trustSourceName,
            timestamp: Date(),
            reportPath: nil
        )
    }

    private func closeTabScript(
        bundleIdentifier: String,
        websiteURL: String?,
        websiteHost: String?
    ) -> String? {
        let escapedURL = escapedAppleScriptString(websiteURL ?? "")
        let escapedHost = escapedAppleScriptString(normalizedHost(websiteHost))

        switch bundleIdentifier {
        case "com.apple.Safari":
            return safariCloseScript(websiteURL: escapedURL, websiteHost: escapedHost)
        case "com.google.Chrome":
            return chromiumCloseScript(applicationName: "Google Chrome", websiteURL: escapedURL, websiteHost: escapedHost)
        case "com.microsoft.edgemac":
            return chromiumCloseScript(applicationName: "Microsoft Edge", websiteURL: escapedURL, websiteHost: escapedHost)
        case "company.thebrowser.Browser":
            return chromiumCloseScript(applicationName: "Arc", websiteURL: escapedURL, websiteHost: escapedHost)
        default:
            return nil
        }
    }

    private func safariCloseScript(websiteURL: String, websiteHost: String) -> String {
        """
        set targetURL to "\(websiteURL)"
        set targetHost to "\(websiteHost)"
        set foundMatch to false
        tell application "Safari"
            repeat with windowIndex from 1 to count of windows
                set tabCount to count of tabs of window windowIndex
                repeat with tabIndex from tabCount to 1 by -1
                    set tabURL to URL of tab tabIndex of window windowIndex
                    if my matchesTarget(tabURL, targetURL, targetHost) then
                        set foundMatch to true
                        if (count of windows) = 1 and (count of tabs of window windowIndex) = 1 then
                            tell window windowIndex to set current tab to (make new tab with properties {URL:"about:blank"})
                        end if
                        close tab tabIndex of window windowIndex
                        delay 0.3
                        if my targetStillOpen(targetURL, targetHost) then
                            return "still-open"
                        end if
                        return "closed"
                    end if
                end repeat
            end repeat
            -- Targeted URL/host pass found nothing. Try the defensive loopback/simulator pass.
            repeat with windowIndex from 1 to count of windows
                set tabCount to count of tabs of window windowIndex
                repeat with tabIndex from tabCount to 1 by -1
                    set tabURL to URL of tab tabIndex of window windowIndex
                    if my isLoopbackOrSimulator(tabURL) then
                        set foundMatch to true
                        if (count of windows) = 1 and (count of tabs of window windowIndex) = 1 then
                            tell window windowIndex to set current tab to (make new tab with properties {URL:"about:blank"})
                        end if
                        close tab tabIndex of window windowIndex
                        delay 0.3
                        return "closed"
                    end if
                end repeat
            end repeat
        end tell
        if foundMatch then
            return "still-open"
        end if
        if my targetStillOpen(targetURL, targetHost) then
            return "still-open"
        end if
        return "absent"

        on targetStillOpen(targetURL, targetHost)
            tell application "Safari"
                repeat with browserWindow in windows
                    repeat with browserTab in tabs of browserWindow
                        set tabURL to URL of browserTab
                        if my matchesTarget(tabURL, targetURL, targetHost) then return true
                    end repeat
                end repeat
            end tell
            return false
        end targetStillOpen

        on matchesTarget(tabURL, targetURL, targetHost)
            if targetURL is not "" then
                if tabURL is targetURL then return true
                if my trimTrailingSlash(tabURL) is my trimTrailingSlash(targetURL) then return true
                return false
            end if
            if targetHost is not "" and targetHost is not "127.0.0.1" and targetHost is not "localhost" and tabURL contains targetHost then return true
            return false
        end matchesTarget

        on isLoopbackOrSimulator(tabURL)
            if tabURL is missing value then return false
            if tabURL contains "://127.0.0.1" then return true
            if tabURL contains "://localhost" then return true
            if tabURL contains "://[::1]" then return true
            if tabURL contains "/camera-upload-test" then return true
            return false
        end isLoopbackOrSimulator

        on trimTrailingSlash(theURL)
            if theURL ends with "/" then return text 1 thru -2 of theURL
            return theURL
        end trimTrailingSlash
        """
    }

    private func chromiumCloseScript(applicationName: String, websiteURL: String, websiteHost: String) -> String {
        """
        set targetURL to "\(websiteURL)"
        set targetHost to "\(websiteHost)"
        set foundMatch to false
        tell application "\(applicationName)"
            repeat with windowIndex from 1 to count of windows
                set tabCount to count of tabs of window windowIndex
                repeat with tabIndex from tabCount to 1 by -1
                    set tabURL to URL of tab tabIndex of window windowIndex
                    if my matchesTarget(tabURL, targetURL, targetHost) then
                        set foundMatch to true
                        if (count of windows) = 1 and (count of tabs of window windowIndex) = 1 then
                            make new tab at end of tabs of window windowIndex with properties {URL:"about:blank"}
                        end if
                        close tab tabIndex of window windowIndex
                        delay 0.3
                        if my targetStillOpen(targetURL, targetHost) then
                            return "still-open"
                        end if
                        return "closed"
                    end if
                end repeat
            end repeat
            -- Targeted URL/host pass found nothing. Try the defensive loopback/simulator pass.
            repeat with windowIndex from 1 to count of windows
                set tabCount to count of tabs of window windowIndex
                repeat with tabIndex from tabCount to 1 by -1
                    set tabURL to URL of tab tabIndex of window windowIndex
                    if my isLoopbackOrSimulator(tabURL) then
                        set foundMatch to true
                        if (count of windows) = 1 and (count of tabs of window windowIndex) = 1 then
                            make new tab at end of tabs of window windowIndex with properties {URL:"about:blank"}
                        end if
                        close tab tabIndex of window windowIndex
                        delay 0.3
                        return "closed"
                    end if
                end repeat
            end repeat
        end tell
        if foundMatch then
            return "still-open"
        end if
        if my targetStillOpen(targetURL, targetHost) then
            return "still-open"
        end if
        return "absent"

        on targetStillOpen(targetURL, targetHost)
            tell application "\(applicationName)"
                repeat with browserWindow in windows
                    repeat with browserTab in tabs of browserWindow
                        set tabURL to URL of browserTab
                        if my matchesTarget(tabURL, targetURL, targetHost) then return true
                    end repeat
                end repeat
            end tell
            return false
        end targetStillOpen

        on matchesTarget(tabURL, targetURL, targetHost)
            if targetURL is not "" then
                if tabURL is targetURL then return true
                if my trimTrailingSlash(tabURL) is my trimTrailingSlash(targetURL) then return true
                return false
            end if
            if targetHost is not "" and targetHost is not "127.0.0.1" and targetHost is not "localhost" and tabURL contains targetHost then return true
            return false
        end matchesTarget

        on isLoopbackOrSimulator(tabURL)
            if tabURL is missing value then return false
            if tabURL contains "://127.0.0.1" then return true
            if tabURL contains "://localhost" then return true
            if tabURL contains "://[::1]" then return true
            if tabURL contains "/camera-upload-test" then return true
            return false
        end isLoopbackOrSimulator

        on trimTrailingSlash(theURL)
            if theURL ends with "/" then return text 1 thru -2 of theURL
            return theURL
        end trimTrailingSlash
        """
    }

    private func normalizedHost(_ host: String?) -> String {
        guard let host else {
            return ""
        }
        return host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
    }

    private func escapedAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
