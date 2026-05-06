import AppKit
import Darwin
import Foundation
import os

@MainActor
final class CameraProtectionService {
    private let logger = Logger(subsystem: "CamGuardMac", category: "CameraProtection")
    private let processIdentificationService = ProcessIdentificationService()
    private let browserTabProtectionService = BrowserTabProtectionService()
    private let criticalProcessNames: Set<String> = [
        "kernel_task",
        "launchd",
        "WindowServer",
        "loginwindow",
        "securityd",
        "tccd",
        "cfprefsd",
        "distnoted",
        "coreaudiod",
        "ControlCenter",
        "SystemUIServer",
        "Finder"
    ]
    private let protectedBundleIdentifiers: Set<String> = [
        "com.apple.finder",
        "com.apple.SystemUIServer",
        "com.apple.loginwindow",
        Bundle.main.bundleIdentifier ?? ""
    ]

    func evaluateProtectionAction(for event: SecurityActivityEvent) -> ProtectionDecision {
        let eventTrustContext = TrustedCameraApplicationPolicy.context(
            for: event.observedApplicationName,
            websiteDomain: event.observedWebsiteHost
        )
        let isUntrustedWebsiteSource = event.isWebsiteAttributed && !eventTrustContext.isTrusted
        let isCriticalWebsiteSource = event.isWebsiteAttributed && event.status == .critical
        let identification = processIdentificationService.identifySuspectedProcess(
            appName: event.observedApplicationName,
            bundleIdentifier: event.observedBundleIdentifier,
            processID: event.observedProcessID
        )

        guard event.status == .suspicious || event.status == .critical else {
            return ProtectionDecision(
                eventID: event.id,
                action: .none,
                confidence: identification.confidence,
                suspectedProcess: identification.process,
                reasons: [],
                requiresConfirmation: false,
                explanation: "The event is classified as normal, so no protection action is needed."
            )
        }

        guard let process = identification.process, identification.confidence != .uncertain else {
            return ProtectionDecision(
                eventID: event.id,
                action: .openPrivacySettings,
                confidence: .uncertain,
                suspectedProcess: nil,
                reasons: [.unknownProcessIdentity, .noActionableProcess, .userConfirmationRequired],
                requiresConfirmation: false,
                explanation: "\(identification.reason) Open macOS Camera Privacy settings and review app access manually."
            )
        }

        if isProtectedProcess(process) {
            return ProtectionDecision(
                eventID: event.id,
                action: .warnOnly,
                confidence: .confirmed,
                suspectedProcess: process,
                reasons: [.systemProcessProtected],
                requiresConfirmation: false,
                explanation: "\(process.appName) is protected and will not be terminated automatically."
            )
        }

        if process.isTrusted && !isCriticalWebsiteSource {
            return ProtectionDecision(
                eventID: event.id,
                action: .warnOnly,
                confidence: identification.confidence,
                suspectedProcess: process,
                reasons: [.trustedApplication, .userConfirmationRequired],
                requiresConfirmation: false,
                explanation: "\(process.appName) is trusted, so CamGuard will not stop it automatically."
            )
        }

        let action: ProtectionAction = isCriticalWebsiteSource ? .closeBrowserTab : .terminateProcess
        return ProtectionDecision(
            eventID: event.id,
            action: action,
            confidence: identification.confidence,
            suspectedProcess: process,
            reasons: event.status == .critical ? [.threatLevelCritical, .untrustedApplication] : [.threatLevelSuspicious, .untrustedApplication],
            requiresConfirmation: identification.confidence != .confirmed,
            explanation: isCriticalWebsiteSource
                ? "\(event.trustSourceName) is the website source using \(process.appName). Critical website camera activity will close the matching browser tab first. \(identification.reason)"
                : "\(process.appName) is associated with suspicious camera activity and is not in the trusted camera app list. \(identification.reason)"
        )
    }

    func closeSuspiciousBrowserTab(event: SecurityActivityEvent, process: ProcessInfoModel) async -> ProtectionResult {
        await browserTabProtectionService.closeTab(for: event, process: process)
    }

    func stopSuspiciousProcess(_ process: ProcessInfoModel, eventID: UUID? = nil, forceIfNeeded: Bool = false) async -> ProtectionResult {
        let resolvedEventID = eventID ?? UUID()
        guard !isProtectedProcess(process) else {
            return ProtectionResult(
                eventID: resolvedEventID,
                action: .warnOnly,
                success: false,
                status: "Manual review required",
                detail: "CamGuard will not terminate protected system or CamGuard processes.",
                confidence: .confirmed,
                processID: process.processID,
                appName: process.appName,
                timestamp: Date(),
                reportPath: nil
            )
        }

        guard let runningApp = NSRunningApplication(processIdentifier: process.processID) else {
            return ProtectionResult(
                eventID: resolvedEventID,
                action: .terminateProcess,
                success: false,
                status: "Failed to stop",
                detail: "The process was no longer running.",
                confidence: .confirmed,
                processID: process.processID,
                appName: process.appName,
                timestamp: Date(),
                reportPath: nil
            )
        }

        guard runningApplication(runningApp, matches: process) else {
            logger.error("Process identity changed before termination for pid \(process.processID, privacy: .public)")
            return ProtectionResult(
                eventID: resolvedEventID,
                action: .terminateProcess,
                success: false,
                status: "Identity changed",
                detail: "macOS reports PID \(process.processID) now belongs to a different app, so CamGuard did not terminate it.",
                confidence: .uncertain,
                processID: process.processID,
                appName: process.appName,
                timestamp: Date(),
                reportPath: nil
            )
        }

        logger.warning("Attempting graceful termination for \(process.appName, privacy: .public)")
        let requested = runningApp.terminate()
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        if requested, runningApp.isTerminated {
            return ProtectionResult(
                eventID: resolvedEventID,
                action: .terminateProcess,
                success: true,
                status: "Stopped",
                detail: "\(process.appName) was stopped gracefully.",
                confidence: .confirmed,
                processID: process.processID,
                appName: process.appName,
                timestamp: Date(),
                reportPath: nil
            )
        }

        if forceIfNeeded {
            logger.warning("Attempting force termination for \(process.appName, privacy: .public)")
            let appKitForced = runningApp.forceTerminate()
            try? await Task.sleep(nanoseconds: 500_000_000)
            if appKitForced, runningApp.isTerminated {
                return ProtectionResult(
                    eventID: resolvedEventID,
                    action: .terminateProcess,
                    success: true,
                    status: "Stopped",
                    detail: "\(process.appName) was force stopped by CamGuard protection policy.",
                    confidence: .confirmed,
                    processID: process.processID,
                    appName: process.appName,
                    timestamp: Date(),
                    reportPath: nil
                )
            }

            logger.warning("Attempting signal termination for \(process.appName, privacy: .public)")
            let signalStopped = await terminateWithSignal(processID: process.processID)
            return ProtectionResult(
                eventID: resolvedEventID,
                action: .terminateProcess,
                success: signalStopped,
                status: signalStopped ? "Stopped" : "Failed to stop",
                detail: signalStopped ? "\(process.appName) was stopped with a direct process signal." : "\(process.appName) did not stop. macOS may be blocking termination or the process may require stronger privileges.",
                confidence: .confirmed,
                processID: process.processID,
                appName: process.appName,
                timestamp: Date(),
                reportPath: nil
            )
        }

        return ProtectionResult(
            eventID: resolvedEventID,
            action: .terminateProcess,
            success: false,
            status: "User confirmation required",
            detail: "\(process.appName) did not stop gracefully. Force termination requires confirmation.",
            confidence: .likely,
            processID: process.processID,
            appName: process.appName,
            timestamp: Date(),
            reportPath: nil
        )
    }

    private func terminateWithSignal(processID: Int32) async -> Bool {
        guard kill(processID, SIGTERM) == 0 || errno == ESRCH else {
            logger.error("SIGTERM failed for pid \(processID, privacy: .public) with errno \(errno, privacy: .public)")
            return false
        }
        try? await Task.sleep(nanoseconds: 800_000_000)
        if kill(processID, 0) != 0 && errno == ESRCH {
            return true
        }

        guard kill(processID, SIGKILL) == 0 || errno == ESRCH else {
            logger.error("SIGKILL failed for pid \(processID, privacy: .public) with errno \(errno, privacy: .public)")
            return false
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        return kill(processID, 0) != 0 && errno == ESRCH
    }

    func requestUserConfirmation(for decision: ProtectionDecision) async -> Bool {
        let appName = decision.suspectedProcess?.appName ?? "Unknown Application"
        let alert = NSAlert()
        alert.messageText = "Confirm Protection Action"
        alert.informativeText = "CamGuard detected suspicious camera behavior, but macOS does not fully confirm the exact camera-owning process. The most likely application is \(appName). Do you want to stop this application?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Stop Application")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func createProtectionAuditLog(event: SecurityActivityEvent, result: ProtectionResult) {
        logger.info("Protection action \(result.status, privacy: .public) for event \(event.id.uuidString, privacy: .public)")
    }

    func openCameraPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else {
            logger.error("Unable to build Camera Privacy settings URL.")
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func isProtectedProcess(_ process: ProcessInfoModel) -> Bool {
        process.isCamGuard
            || process.isSystemCritical
            || process.processID <= 1
            || criticalProcessNames.contains(process.appName)
            || protectedBundleIdentifiers.contains(process.bundleIdentifier ?? "")
    }

    private func runningApplication(_ runningApp: NSRunningApplication, matches process: ProcessInfoModel) -> Bool {
        if let expectedBundle = process.bundleIdentifier, !expectedBundle.isEmpty {
            return runningApp.bundleIdentifier == expectedBundle
        }

        guard let runningName = runningApp.localizedName else {
            return false
        }
        return runningName.localizedCaseInsensitiveCompare(process.appName) == .orderedSame
    }
}
