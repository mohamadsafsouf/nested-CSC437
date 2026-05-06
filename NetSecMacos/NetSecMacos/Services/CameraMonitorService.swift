import AppKit
import AVFoundation
import Foundation
import os

struct CameraMonitorSnapshot: Equatable {
    let permissionStatus: AVAuthorizationStatus
    let isCameraInUse: Bool
    let cameraNames: [String]
    let observedApplicationName: String?
    let observedProcessID: Int32?
    let observedBundleIdentifier: String?
    let browserContext: BrowserActivityContext?
}

@MainActor
final class CameraMonitorService {
    var onEvent: ((SecurityActivityEvent) -> Void)?
    var onSnapshot: ((CameraMonitorSnapshot) -> Void)?

    private var monitorTask: Task<Void, Never>?
    private var lastSnapshot: CameraMonitorSnapshot?
    private let hardwareUsageDetector = CameraHardwareUsageDetector()
    private let browserContextService = BrowserActivityContextService()
    private let logger = Logger(subsystem: "CamGuardMac", category: "CameraMonitor")

    var isRunning: Bool {
        monitorTask != nil
    }

    func start() {
        guard monitorTask == nil else {
            return
        }

        logger.info("Starting camera monitor.")
        emit(
            SecurityActivityEvent(
                kind: .monitoring,
                title: "Monitoring started",
                detail: "CamGuard is watching camera hardware and permission changes on this Mac.",
                status: .normal
            )
        )

        monitorTask = Task { [weak self] in
            await self?.requestCameraPermissionIfNeeded()
            while !Task.isCancelled {
                await self?.pollOnce()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        lastSnapshot = nil
        logger.info("Stopped camera monitor.")
    }

    private func pollOnce() async {
        let snapshot = currentSnapshot()
        onSnapshot?(snapshot)

        guard snapshot != lastSnapshot else {
            return
        }

        emitEvents(for: snapshot, previous: lastSnapshot)
        lastSnapshot = snapshot
    }

    private func currentSnapshot() -> CameraMonitorSnapshot {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        let devices = discoverySession.devices
        let permissionStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let avFoundationInUse = devices.contains { device in
            device.isInUseByAnotherApplication
        }
        let hardwareUsage = hardwareUsageDetector.snapshot()
        let cameraNames = hardwareUsage.runningDeviceNames.isEmpty ? devices.map(\.localizedName) : hardwareUsage.runningDeviceNames

        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let browserContext = browserContextService.context(for: frontmostApp)

        return CameraMonitorSnapshot(
            permissionStatus: permissionStatus,
            isCameraInUse: avFoundationInUse || hardwareUsage.isRunning,
            cameraNames: cameraNames,
            observedApplicationName: frontmostApp?.localizedName,
            observedProcessID: frontmostApp?.processIdentifier,
            observedBundleIdentifier: frontmostApp?.bundleIdentifier,
            browserContext: browserContext
        )
    }

    private func emitEvents(for snapshot: CameraMonitorSnapshot, previous: CameraMonitorSnapshot?) {
        if previous?.permissionStatus != snapshot.permissionStatus {
            emit(permissionEvent(for: snapshot.permissionStatus))
        }

        guard previous?.isCameraInUse != snapshot.isCameraInUse else {
            return
        }

        if snapshot.isCameraInUse {
            let cameraName = snapshot.cameraNames.first ?? "Camera"
            let observedApp = snapshot.observedApplicationName
            let browserContext = snapshot.browserContext
            let trustContext = TrustedCameraApplicationPolicy.context(
                for: observedApp,
                websiteDomain: browserContext?.host
            )
            let detail: String
            if let observedApp, !observedApp.isEmpty {
                detail = "\(cameraName) is active. The frontmost app is \(observedApp); macOS does not reveal the exact camera-owning process to other apps.\(browserContext?.detailSuffix ?? "")"
            } else {
                detail = "\(cameraName) is active in another application."
            }

            emit(
                SecurityActivityEvent(
                    kind: .cameraStatus,
                    title: "Camera activity detected",
                    detail: detail,
                    status: trustContext.isTrusted ? .normal : .suspicious,
                    observedApplicationName: trustContext.displayName,
                    observedProcessID: snapshot.observedProcessID,
                    observedBundleIdentifier: snapshot.observedBundleIdentifier,
                    observedWebsiteURL: browserContext?.url,
                    observedWebsiteHost: browserContext?.host
                )
            )
        } else if previous != nil {
            emit(
                SecurityActivityEvent(
                    kind: .cameraStatus,
                    title: "Camera activity ended",
                    detail: "No active external camera session is currently reported by macOS.",
                    status: .normal
                )
            )
        }
    }

    private func requestCameraPermissionIfNeeded() async {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined else {
            return
        }

        emit(
            SecurityActivityEvent(
                kind: .permissionStatus,
                title: "Camera permission requested",
                detail: "CamGuard requests permission only to check camera status. It does not record or upload camera media.",
                status: .normal
            )
        )

        let granted = await AVCaptureDevice.requestAccess(for: .video)
        emit(
            SecurityActivityEvent(
                kind: .permissionStatus,
                title: granted ? "Camera permission authorized" : "Camera permission denied",
                detail: granted ? "Realtime camera status checks are enabled." : "CamGuard will keep using hardware status signals where macOS allows it.",
                status: granted ? .normal : .suspicious
            )
        )
    }

    private func permissionEvent(for status: AVAuthorizationStatus) -> SecurityActivityEvent {
        switch status {
        case .authorized:
            return SecurityActivityEvent(
                kind: .permissionStatus,
                title: "Camera permission authorized",
                detail: "CamGuard can perform approved camera permission checks.",
                status: .normal
            )
        case .denied, .restricted:
            return SecurityActivityEvent(
                kind: .permissionStatus,
                title: "Camera permission unavailable",
                detail: "Camera access is denied or restricted. Monitoring can still watch external use status when macOS reports it.",
                status: .suspicious
            )
        case .notDetermined:
            return SecurityActivityEvent(
                kind: .permissionStatus,
                title: "Camera permission not requested",
                detail: "CamGuard has not requested camera access. Media is not captured.",
                status: .normal
            )
        @unknown default:
            return SecurityActivityEvent(
                kind: .permissionStatus,
                title: "Unknown camera permission state",
                detail: "macOS returned an unrecognized camera permission state.",
                status: .suspicious
            )
        }
    }

    private func emit(_ event: SecurityActivityEvent) {
        logger.info("Camera monitor event: \(event.title, privacy: .public)")
        onEvent?(event)
    }
}
