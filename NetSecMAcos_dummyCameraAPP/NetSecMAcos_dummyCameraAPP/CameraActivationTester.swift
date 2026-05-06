import AVFoundation
import Combine
import CoreMedia
import Foundation
import os

@MainActor
final class CameraActivationTester: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published private(set) var permissionStatusTitle = "Not Requested"
    @Published private(set) var statusMessage = "Ready. Start CamGuard monitoring, then run the repeated test here."
    @Published private(set) var isCameraRunning = false
    @Published private(set) var isSequenceRunning = false
    @Published private(set) var activationCount = 0
    @Published private(set) var shortActivationCount = 0
    @Published private(set) var threatLevel = "Normal"
    @Published private(set) var eventLog: [String] = ["No camera events yet."]
    @Published private(set) var metadataStatus = "Metadata sync is optional."
    @Published private(set) var networkTestStatus = "Camera + network test is ready."
    @Published var backendURLString = "http://127.0.0.1:8000/api/v1"
    @Published var deviceIDString = ""
    @Published var bearerToken = ""

    private let logger = Logger(subsystem: "UnknownCameraClient", category: "CameraTest")
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let videoOutputQueue = DispatchQueue(label: "UnknownCameraClient.DiscardedVideoFrames")
    private var sequenceTask: Task<Void, Never>?
    private var recentShortActivations: [Date] = []
    private var lastDurationSeconds: Double?

    private let shortActivationLimit: TimeInterval = 5
    private let repeatedWindow: TimeInterval = 600
    private let repeatedThreshold = 3

    var canSendMetadata: Bool {
        URL(string: backendURLString) != nil
            && UUID(uuidString: deviceIDString) != nil
            && !bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canRunNetworkTest: Bool {
        URL(string: backendURLString) != nil
    }

    override init() {
        super.init()
        refreshPermissionStatus()
    }

    func requestCameraPermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        guard status == .notDetermined else {
            refreshPermissionStatus()
            statusMessage = "Camera permission is already \(permissionStatusTitle.lowercased())."
            return
        }

        logger.info("Requesting camera permission.")
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        refreshPermissionStatus()
        statusMessage = granted ? "Camera permission granted." : "Camera permission denied. Enable access in System Settings to run this test."
        addEvent(granted ? "Permission granted" : "Permission denied")
    }

    func openCameraOnce() {
        guard !isSequenceRunning else {
            return
        }

        sequenceTask = Task { [weak self] in
            guard let self else { return }
            self.isSequenceRunning = true
            await self.performActivation(label: "Manual activation", sendNetworkActivity: false)
            self.isSequenceRunning = false
        }
    }

    func runCameraNetworkActivityTest() {
        guard !isSequenceRunning else {
            return
        }

        sequenceTask = Task { [weak self] in
            guard let self else { return }
            self.isSequenceRunning = true
            await self.performActivation(label: "Camera + network test", sendNetworkActivity: true)
            self.isSequenceRunning = false
        }
    }

    func runCriticalCameraMetadataTest() {
        guard !isSequenceRunning else {
            return
        }

        guard canRunNetworkTest else {
            metadataStatus = "Enter a valid backend URL before running Critical Test."
            statusMessage = "Critical Test needs the backend URL first."
            addEvent("Critical test setup required")
            logger.warning("Critical test needs a valid backend URL.")
            return
        }

        sequenceTask = Task { [weak self] in
            guard let self else { return }
            self.isSequenceRunning = true
            await self.performActivation(label: "Critical camera + network metadata test", sendNetworkActivity: true, shouldSendCriticalMetadata: true)
            self.isSequenceRunning = false
        }
    }

    func runRepeatedShortActivationTest() {
        guard !isSequenceRunning else {
            return
        }

        sequenceTask = Task { [weak self] in
            guard let self else { return }
            self.isSequenceRunning = true
            self.statusMessage = "Running repeated short activation test."

            for index in 1...3 {
                guard !Task.isCancelled else { break }
                await self.performActivation(label: "Repeated test \(index) of 3", sendNetworkActivity: false)

                guard index < 3, !Task.isCancelled else { continue }
                self.statusMessage = "Camera closed. Waiting 15 seconds before activation \(index + 1)."
                try? await Task.sleep(for: .seconds(15))
            }

            self.isSequenceRunning = false
            if !Task.isCancelled {
                self.statusMessage = "Repeated test complete. CamGuard should flag repeated short camera activations."
            }
        }
    }

    func cancelSequence() {
        sequenceTask?.cancel()
        sequenceTask = nil
        stopCamera()
        isSequenceRunning = false
        statusMessage = "Camera test stopped."
        addEvent("Test cancelled")
    }

    func sendDummyMetadata() async {
        guard let baseURL = URL(string: backendURLString),
              let deviceID = UUID(uuidString: deviceIDString) else {
            metadataStatus = "Enter a valid backend URL and device UUID."
            logger.warning("Rejected metadata sync because backend URL or device UUID was invalid.")
            return
        }

        let token = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            metadataStatus = "Enter a bearer token if you want to send metadata."
            return
        }

        do {
            var request = URLRequest(url: baseURL.appending(path: "/events/camera"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(dummyPayload(deviceID: deviceID))

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                metadataStatus = "Metadata sync failed: invalid backend response."
                logger.error("Metadata sync failed because response was not HTTP.")
                return
            }

            if (200..<300).contains(httpResponse.statusCode) {
                metadataStatus = "Dummy metadata sent. No camera content was uploaded."
                addEvent("Dummy metadata sent")
            } else {
                metadataStatus = "Metadata sync failed with HTTP \(httpResponse.statusCode)."
                logger.warning("Metadata sync failed with status \(httpResponse.statusCode, privacy: .public).")
            }
        } catch {
            metadataStatus = "Metadata sync failed: \(error.localizedDescription)"
            logger.error("Metadata sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func performActivation(
        label: String,
        sendNetworkActivity: Bool,
        shouldSendCriticalMetadata: Bool = false
    ) async {
        guard await ensureCameraPermission() else {
            return
        }

        do {
            try startCamera()
            activationCount += 1
            statusMessage = "\(label): camera open for 3 seconds."
            addEvent("\(label) opened")

            try await Task.sleep(for: .seconds(3))
            stopCamera()
            recordClosedActivation(duration: 3)
            if sendNetworkActivity {
                await sendSimulatedNetworkActivity()
            }
            if shouldSendCriticalMetadata {
                await sendCriticalMetadata()
            }
        } catch {
            stopCamera()
            statusMessage = "Camera test failed: \(error.localizedDescription)"
            logger.error("Camera activation failed: \(error.localizedDescription, privacy: .public)")
            addEvent("Activation failed")
        }
    }

    private func ensureCameraPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            refreshPermissionStatus()
            return true
        case .notDetermined:
            await requestCameraPermission()
            return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        case .denied, .restricted:
            refreshPermissionStatus()
            statusMessage = "Camera permission is denied or restricted. Enable it in System Settings."
            addEvent("Permission unavailable")
            return false
        @unknown default:
            refreshPermissionStatus()
            statusMessage = "macOS returned an unknown camera permission state."
            logger.warning("Unknown camera authorization status.")
            return false
        }
    }

    private func startCamera() throws {
        guard !isCameraRunning else {
            return
        }

        guard let device = AVCaptureDevice.default(for: .video) else {
            throw CameraTesterError.noCameraAvailable
        }

        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .low
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraTesterError.inputUnavailable
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoOutputQueue)
        guard session.canAddOutput(output) else {
            throw CameraTesterError.outputUnavailable
        }
        session.addOutput(output)
        session.commitConfiguration()
        session.startRunning()

        captureSession = session
        videoOutput = output
        isCameraRunning = true
        logger.info("Camera session started with discard-only video output.")
    }

    private func stopCamera() {
        guard let session = captureSession else {
            isCameraRunning = false
            return
        }

        session.stopRunning()
        for input in session.inputs {
            session.removeInput(input)
        }
        for output in session.outputs {
            session.removeOutput(output)
        }
        captureSession = nil
        videoOutput = nil
        isCameraRunning = false
        logger.info("Camera session stopped.")
    }

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Intentionally discard frames. This activates hardware without recording, saving, or uploading media.
    }

    private func recordClosedActivation(duration: TimeInterval) {
        lastDurationSeconds = duration
        if duration < shortActivationLimit {
            recentShortActivations.append(Date())
        }

        let cutoff = Date().addingTimeInterval(-repeatedWindow)
        recentShortActivations.removeAll { $0 < cutoff }
        shortActivationCount = recentShortActivations.count
        threatLevel = shortActivationCount >= repeatedThreshold ? "Suspicious" : "Normal"

        let detail = "Closed after \(Int(duration)) seconds. Short activations in 10 minutes: \(shortActivationCount)."
        statusMessage = detail
        addEvent(detail)
    }

    private func sendSimulatedNetworkActivity() async {
        guard let baseURL = URL(string: backendURLString) else {
            networkTestStatus = "Enter a valid backend URL before running the network test."
            logger.warning("Rejected camera network test because backend URL was invalid.")
            return
        }

        do {
            var request = URLRequest(url: baseURL.appending(path: "/events/simulated-camera-network-activity"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body = SimulatedCameraNetworkActivityPayload(
                eventType: "simulated_camera_network_activity",
                appName: "UnknownCameraClient",
                dummyUpload: true,
                payload: "test_only_no_camera_media",
                durationSeconds: lastDurationSeconds ?? 3,
                activationCountRecentWindow: max(shortActivationCount, 1)
            )

            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                networkTestStatus = "Network test failed: invalid backend response."
                logger.error("Network test failed because response was not HTTP.")
                return
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                networkTestStatus = "Network test failed with HTTP \(httpResponse.statusCode)."
                logger.warning("Network test failed with status \(httpResponse.statusCode, privacy: .public).")
                return
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let result = try decoder.decode(SimulatedCameraNetworkActivityResponse.self, from: data)
            threatLevel = result.threatLevel.capitalized
            networkTestStatus = "\(result.reason). Backend threat level: \(result.threatLevel.capitalized)."
            addEvent("Dummy network request sent after camera close")
        } catch {
            networkTestStatus = "Network test failed: \(error.localizedDescription)"
            logger.error("Network test failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func sendCriticalMetadata() async {
        guard let baseURL = URL(string: backendURLString) else {
            metadataStatus = "Enter a valid backend URL before running the critical test."
            logger.warning("Rejected critical metadata sync because backend URL was invalid.")
            return
        }

        do {
            var request = URLRequest(url: baseURL.appending(path: "/events/local-critical-camera-test"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(
                LocalCriticalCameraEventPayload(
                    appName: "UnknownCameraClient",
                    bundleIdentifier: Bundle.main.bundleIdentifier,
                    processId: Int(ProcessInfo.processInfo.processIdentifier),
                    durationSeconds: lastDurationSeconds ?? 3,
                    activationCountRecentWindow: max(shortActivationCount, repeatedThreshold)
                )
            )

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                metadataStatus = "Critical metadata failed: invalid backend response."
                logger.error("Critical metadata failed because response was not HTTP.")
                return
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                metadataStatus = "Critical metadata failed with HTTP \(httpResponse.statusCode)."
                logger.warning("Critical metadata failed with status \(httpResponse.statusCode, privacy: .public).")
                return
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let result = try decoder.decode(CameraEventSyncResponse.self, from: data)
            threatLevel = result.score.threatLevel.capitalized
            metadataStatus = "Critical metadata saved. Backend threat level: \(result.score.threatLevel.capitalized)."
            addEvent("Critical camera + network metadata saved")
        } catch {
            metadataStatus = "Critical metadata failed: \(error.localizedDescription)"
            logger.error("Critical metadata failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func refreshPermissionStatus() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionStatusTitle = "Authorized"
        case .denied:
            permissionStatusTitle = "Denied"
        case .restricted:
            permissionStatusTitle = "Restricted"
        case .notDetermined:
            permissionStatusTitle = "Not Requested"
        @unknown default:
            permissionStatusTitle = "Unknown"
        }
    }

    private func addEvent(_ message: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        eventLog.insert("\(timestamp)  \(message)", at: 0)
        eventLog = Array(eventLog.prefix(8))
    }

    private func dummyPayload(
        deviceID: UUID,
        networkUploadAfterCamera: Bool = false,
        activationCountRecentWindow: Int? = nil,
        isRepeatedShortActivation: Bool? = nil,
        simulationLabel: String? = nil,
        notes: String = "Dummy metadata from UnknownCameraClient. No video, images, or camera content included."
    ) -> CameraEventPayload {
        CameraEventPayload(
            clientEventId: UUID(),
            deviceId: deviceID,
            eventType: "camera_session",
            cameraStatus: "ended",
            permissionStatus: permissionStatusKey(),
            occurredAt: Date(),
            collectedAt: Date(),
            application: CameraApplicationPayload(
                displayName: "UnknownCameraClient",
                bundleIdentifier: Bundle.main.bundleIdentifier,
                processId: Int(ProcessInfo.processInfo.processIdentifier),
                signingTeamId: nil,
                isTrusted: false,
                isKnown: false
            ),
            durationSeconds: lastDurationSeconds ?? 3,
            activationCountRecentWindow: activationCountRecentWindow ?? shortActivationCount,
            recentWindowSeconds: Int(repeatedWindow),
            isBackgroundAccess: false,
            isRepeatedShortActivation: isRepeatedShortActivation ?? (shortActivationCount >= repeatedThreshold),
            networkUploadAfterCamera: networkUploadAfterCamera,
            networkWindowSeconds: 30,
            isSimulated: simulationLabel != nil,
            simulationLabel: simulationLabel,
            notes: notes
        )
    }

    private func permissionStatusKey() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "not_determined"
        @unknown default:
            return "unknown"
        }
    }
}

private enum CameraTesterError: LocalizedError {
    case noCameraAvailable
    case inputUnavailable
    case outputUnavailable

    var errorDescription: String? {
        switch self {
        case .noCameraAvailable:
            return "No camera is available on this Mac."
        case .inputUnavailable:
            return "The camera input could not be added to the test session."
        case .outputUnavailable:
            return "The discard-only video output could not be added to the test session."
        }
    }
}

private struct CameraEventPayload: Encodable {
    let clientEventId: UUID
    let deviceId: UUID
    let eventType: String
    let cameraStatus: String
    let permissionStatus: String
    let occurredAt: Date
    let collectedAt: Date
    let application: CameraApplicationPayload
    let durationSeconds: Double
    let activationCountRecentWindow: Int
    let recentWindowSeconds: Int
    let isBackgroundAccess: Bool
    let isRepeatedShortActivation: Bool
    let networkUploadAfterCamera: Bool
    let networkWindowSeconds: Int
    let isSimulated: Bool
    let simulationLabel: String?
    let notes: String
}

private struct CameraApplicationPayload: Encodable {
    let displayName: String
    let bundleIdentifier: String?
    let processId: Int
    let signingTeamId: String?
    let isTrusted: Bool
    let isKnown: Bool
}

private struct SimulatedCameraNetworkActivityPayload: Encodable {
    let eventType: String
    let appName: String
    let dummyUpload: Bool
    let payload: String
    let durationSeconds: Double
    let activationCountRecentWindow: Int
}

private struct SimulatedCameraNetworkActivityResponse: Decodable {
    let detected: Bool
    let reason: String
    let threatLevel: String
}

private struct LocalCriticalCameraEventPayload: Encodable {
    let appName: String
    let bundleIdentifier: String?
    let processId: Int
    let durationSeconds: Double
    let activationCountRecentWindow: Int
}

private struct CameraEventSyncResponse: Decodable {
    let saved: Bool
    let score: CameraEventScore
}

private struct CameraEventScore: Decodable {
    let threatLevel: String
}
