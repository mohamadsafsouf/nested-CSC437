import AVFoundation
import Foundation
import os

struct CameraSessionSnapshot: Equatable {
    let isRunning: Bool
    let permissionState: CameraPermissionState
    let startedAt: Date?
}

final class CameraSessionService {
    var onSnapshot: ((CameraSessionSnapshot) -> Void)?

    private let permissionService: CameraPermissionService
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.camguard.ios.camera-session")
    private let logger = Logger(subsystem: "CamGuardiOS", category: "CameraSession")
    private var startedAt: Date?

    init(permissionService: CameraPermissionService = CameraPermissionService()) {
        self.permissionService = permissionService
    }

    func snapshot() -> CameraSessionSnapshot {
        CameraSessionSnapshot(
            isRunning: session.isRunning,
            permissionState: permissionService.currentState(),
            startedAt: startedAt
        )
    }

    func startSafetyTest() async throws -> CameraSessionSnapshot {
        var state = permissionService.currentState()
        if state == .notDetermined {
            state = await permissionService.requestAccess()
        }

        guard state == .authorized else {
            let snapshot = CameraSessionSnapshot(isRunning: false, permissionState: state, startedAt: nil)
            notify(snapshot)
            throw CameraSessionError.permissionRequired(state)
        }

        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    try configureSessionIfNeeded()
                    if !session.isRunning {
                        session.startRunning()
                    }
                    startedAt = Date()
                    let snapshot = CameraSessionSnapshot(isRunning: session.isRunning, permissionState: state, startedAt: startedAt)
                    notify(snapshot)
                    continuation.resume(returning: ())
                } catch {
                    logger.error("Camera safety test could not start: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: error)
                }
            }
        }

        return snapshot()
    }

    func stopSafetyTest() async -> CameraSessionSnapshot {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if session.isRunning {
                    session.stopRunning()
                }
                startedAt = nil
                let snapshot = CameraSessionSnapshot(isRunning: false, permissionState: permissionService.currentState(), startedAt: nil)
                notify(snapshot)
                continuation.resume(returning: ())
            }
        }

        return snapshot()
    }

    private func configureSessionIfNeeded() throws {
        guard session.inputs.isEmpty else {
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .low
        defer {
            session.commitConfiguration()
        }

        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
        guard let device else {
            throw CameraSessionError.noCameraAvailable
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraSessionError.cannotAddCameraInput
        }

        session.addInput(input)
    }

    private func notify(_ snapshot: CameraSessionSnapshot) {
        DispatchQueue.main.async { [onSnapshot] in
            onSnapshot?(snapshot)
        }
    }
}

enum CameraSessionError: LocalizedError {
    case permissionRequired(CameraPermissionState)
    case noCameraAvailable
    case cannotAddCameraInput

    var errorDescription: String? {
        switch self {
        case .permissionRequired(let state):
            return "Camera safety test cannot start because permission is \(state.title.lowercased())."
        case .noCameraAvailable:
            return "No camera is available on this device."
        case .cannotAddCameraInput:
            return "CamGuard could not prepare the camera input."
        }
    }
}
