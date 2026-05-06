import AppKit
import Foundation
import os

struct ProcessIdentificationResult {
    let process: ProcessInfoModel?
    let confidence: ProtectionConfidence
    let reason: String
}

@MainActor
final class ProcessIdentificationService {
    private let logger = Logger(subsystem: "CamGuardMac", category: "ProcessIdentification")

    func identifySuspectedProcess(
        appName: String?,
        bundleIdentifier: String?,
        processID: Int32?
    ) -> ProcessIdentificationResult {
        let normalizedName = appName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBundle = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let processID,
           let runningApp = NSRunningApplication(processIdentifier: processID),
           let normalizedBundle,
           runningApp.bundleIdentifier == normalizedBundle {
            let reason = "The event supplied a process ID and the current running application still matches the expected bundle identifier."
            return ProcessIdentificationResult(
                process: processInfo(from: runningApp, fallbackName: normalizedName, bundleIdentifier: normalizedBundle, reason: reason),
                confidence: .confirmed,
                reason: reason
            )
        }

        if let processID,
           let runningApp = NSRunningApplication(processIdentifier: processID),
           namesMatch(runningApp.localizedName, normalizedName) {
            let reason = "The event supplied a process ID and the current running application name matches the suspicious event."
            return ProcessIdentificationResult(
                process: processInfo(from: runningApp, fallbackName: normalizedName, bundleIdentifier: normalizedBundle, reason: reason),
                confidence: .likely,
                reason: reason
            )
        }

        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            if let normalizedBundle, frontmostApp.bundleIdentifier == normalizedBundle {
                let reason = "The frontmost application bundle identifier matched the suspicious camera event."
                return ProcessIdentificationResult(
                    process: processInfo(from: frontmostApp, fallbackName: normalizedName, bundleIdentifier: normalizedBundle, reason: reason),
                    confidence: .confirmed,
                    reason: reason
                )
            }

            if namesMatch(frontmostApp.localizedName, normalizedName) {
                let reason = "The frontmost application name matched the suspicious camera event."
                return ProcessIdentificationResult(
                    process: processInfo(from: frontmostApp, fallbackName: normalizedName, bundleIdentifier: normalizedBundle, reason: reason),
                    confidence: .likely,
                    reason: reason
                )
            }
        }

        let runningMatches = NSWorkspace.shared.runningApplications.filter { app in
            runningApplication(app, matchesName: normalizedName, bundleIdentifier: normalizedBundle)
        }

        if runningMatches.count == 1, let match = runningMatches.first {
            let reason = "Exactly one running application matched the suspicious event."
            return ProcessIdentificationResult(
                process: processInfo(from: match, fallbackName: normalizedName, bundleIdentifier: normalizedBundle, reason: reason),
                confidence: .likely,
                reason: reason
            )
        }

        if runningMatches.count > 1 {
            return ProcessIdentificationResult(
                process: nil,
                confidence: .uncertain,
                reason: "Multiple running applications matched the suspicious event, so CamGuard cannot safely choose one."
            )
        }

        if let pgrepResult = identifyWithPgrep(appName: normalizedName) {
            return pgrepResult
        }

        return ProcessIdentificationResult(
            process: nil,
            confidence: .uncertain,
            reason: "No running application could be confidently matched to the suspicious camera event."
        )
    }

    private func identifyWithPgrep(appName: String?) -> ProcessIdentificationResult? {
        guard let appName, !appName.isEmpty else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-fl", appName]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.error("pgrep process identification failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let matches = output
            .split(separator: "\n")
            .compactMap { line -> Int32? in
                let pieces = line.split(separator: " ", maxSplits: 1)
                guard let first = pieces.first, let pid = Int32(first) else {
                    return nil
                }
                return pid
            }
            .filter { $0 != ProcessInfo.processInfo.processIdentifier }

        guard matches.count == 1, let pid = matches.first else {
            return matches.isEmpty ? nil : ProcessIdentificationResult(
                process: nil,
                confidence: .uncertain,
                reason: "The system process lookup found multiple matches, so CamGuard cannot safely choose one."
            )
        }

        return ProcessIdentificationResult(
            process: ProcessInfoModel(
                processID: pid,
                appName: appName,
                bundleIdentifier: nil,
                identificationReason: "The system process lookup found one matching process name.",
                isTrusted: TrustedCameraApplicationPolicy.context(for: appName).isTrusted,
                isSystemCritical: false,
                isCamGuard: pid == ProcessInfo.processInfo.processIdentifier
            ),
            confidence: .likely,
            reason: "The system process lookup found one matching process name."
        )
    }

    private func processInfo(
        from app: NSRunningApplication,
        fallbackName: String?,
        bundleIdentifier: String?,
        reason: String
    ) -> ProcessInfoModel {
        let appName = app.localizedName ?? fallbackName ?? "Unknown Application"
        let trustContext = TrustedCameraApplicationPolicy.context(for: appName)
        return ProcessInfoModel(
            processID: app.processIdentifier,
            appName: appName,
            bundleIdentifier: app.bundleIdentifier ?? bundleIdentifier,
            identificationReason: reason,
            isTrusted: trustContext.isTrusted,
            isSystemCritical: false,
            isCamGuard: app.processIdentifier == ProcessInfo.processInfo.processIdentifier
        )
    }

    private func runningApplication(
        _ app: NSRunningApplication,
        matchesName appName: String?,
        bundleIdentifier: String?
    ) -> Bool {
        if let bundleIdentifier, !bundleIdentifier.isEmpty, app.bundleIdentifier == bundleIdentifier {
            return true
        }
        return namesMatch(app.localizedName, appName)
    }

    private func namesMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs, !rhs.isEmpty else {
            return false
        }
        return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedSame
    }
}
