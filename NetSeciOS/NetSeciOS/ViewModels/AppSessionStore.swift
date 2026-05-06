import Foundation
import Combine
import os
import UIKit

@MainActor
final class AppSessionStore: ObservableObject {
    @Published private(set) var currentUser: AppUser?
    @Published private(set) var currentSession: AuthSession?
    @Published private(set) var registeredDevices: [RegisteredDevice] = []
    @Published private(set) var currentDevice: RegisteredDevice?
    @Published private(set) var isSyncingDevices = false
    @Published private(set) var activityEvents: [SecurityActivityEvent] = []
    @Published private(set) var isAuthenticating = false
    @Published private(set) var backendConnectionState: BackendConnectionState = .unchecked
    @Published private(set) var cameraPermissionState: CameraPermissionState = .unknown
    @Published private(set) var isCameraTestRunning = false
    @Published private(set) var lastMetadataPayload: CameraEventSyncRequest?
    @Published private(set) var healthKPIs: [HealthKPI] = []
    @Published var selectedTab: AppTab {
        didSet {
            persistence.saveLastSelectedTab(selectedTab)
        }
    }
    @Published var errorMessage: String?
    @Published var monitoringSnapshots: [MonitoringSnapshot] = MonitoringSnapshot.sample

    private let persistence: SessionPersistenceService
    private let authClient: AuthAPIClient
    private let deviceClient: DeviceAPIClient
    private let eventClient: EventAPIClient
    private let deviceMetadataProvider: LocalDeviceMetadataProvider
    private let cameraPermissionService: CameraPermissionService
    private let cameraSessionService: CameraSessionService
    private let reportGenerator: SecurityReportGenerator
    private let logger = Logger(subsystem: "CamGuardiOS", category: "AppSession")
    private var cameraTestStartedAt: Date?
    private var savedEventRefreshTask: Task<Void, Never>?

    var isSignedIn: Bool {
        currentUser != nil && currentSession != nil
    }

    var backendBaseURL: URL {
        authClient.baseURL
    }

    init() {
        let persistence = SessionPersistenceService()
        self.persistence = persistence
        self.authClient = AuthAPIClient()
        self.deviceClient = DeviceAPIClient()
        self.eventClient = EventAPIClient()
        self.deviceMetadataProvider = LocalDeviceMetadataProvider()
        self.cameraPermissionService = CameraPermissionService()
        self.cameraSessionService = CameraSessionService(permissionService: cameraPermissionService)
        self.reportGenerator = SecurityReportGenerator()
        self.selectedTab = persistence.loadLastSelectedTab()
        restorePersistedSession(from: persistence)
        configureCameraSession()
        refreshPermissionState(recordEvent: false)
        recordPrivacyBoundary()
        rebuildHealthKPIs()
        if isSignedIn {
            startSavedEventRefresh()
        }
    }

    func signIn(email: String, password: String) async {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard validateAuthInput(email: normalizedEmail, password: password, requireDisplayName: false, displayName: nil) else {
            return
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let response = try await authClient.signIn(email: normalizedEmail, password: password)
            try persistAuthenticatedResponse(response)
            await syncCurrentDevice()
            startSavedEventRefresh()
            logger.info("Signed in through CamGuard API for \(normalizedEmail, privacy: .private)")
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Backend sign in failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func signUp(email: String, password: String, displayName: String) async {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validateAuthInput(email: normalizedEmail, password: password, requireDisplayName: true, displayName: normalizedName) else {
            return
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let response = try await authClient.signUp(email: normalizedEmail, password: password, displayName: normalizedName)
            if response.session == nil {
                errorMessage = "Account created. Check your email to confirm the account, then sign in."
            } else {
                try persistAuthenticatedResponse(response)
                await syncCurrentDevice()
                startSavedEventRefresh()
            }
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Backend sign up failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func signOut() async {
        let accessToken = currentSession?.accessToken

        if let accessToken {
            do {
                try await authClient.signOut(accessToken: accessToken)
            } catch {
                logger.error("Backend sign out failed, clearing local session anyway: \(error.localizedDescription, privacy: .public)")
            }
        }

        _ = await cameraSessionService.stopSafetyTest()
        savedEventRefreshTask?.cancel()
        savedEventRefreshTask = nil
        currentUser = nil
        currentSession = nil
        currentDevice = nil
        registeredDevices = []
        activityEvents = []
        selectedTab = .overview
        errorMessage = nil
        lastMetadataPayload = nil
        isCameraTestRunning = false
        cameraTestStartedAt = nil
        persistence.clearUser()
        persistence.clearSession()
        persistence.saveLastSelectedTab(.overview)
        refreshPermissionState(recordEvent: false)
        recordPrivacyBoundary()
        rebuildHealthKPIs()
    }

    func resendConfirmation(email: String) async {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedEmail.contains("@"), normalizedEmail.contains(".") else {
            errorMessage = "Enter a valid email address before resending confirmation."
            return
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            try await authClient.resendConfirmation(email: normalizedEmail)
            errorMessage = "Confirmation email sent. Use the newest email link."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    func checkBackendConnection() async {
        backendConnectionState = .checking

        do {
            let response = try await authClient.healthCheck()
            backendConnectionState = .connected(service: response.service)
        } catch {
            backendConnectionState = .disconnected(message: "CamGuard service is temporarily unavailable. Local iOS checks still work.")
            logger.error("Backend health check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func validateRestoredSession() async {
        guard let session = currentSession else {
            return
        }

        do {
            let userDTO = try await authClient.currentUser(accessToken: session.accessToken)
            let user = AppUser(
                id: userDTO.id,
                email: userDTO.email ?? currentUser?.email ?? "",
                displayName: userDTO.displayName ?? currentUser?.displayName ?? "CamGuard User",
                signedInAt: currentUser?.signedInAt ?? Date()
            )
            currentUser = user
            persistence.saveUser(user)
            await syncCurrentDevice()
            startSavedEventRefresh()
        } catch {
            currentUser = nil
            currentSession = nil
            currentDevice = nil
            registeredDevices = []
            activityEvents = []
            persistence.clearUser()
            persistence.clearSession()
            errorMessage = "Your session expired. Please sign in again."
        }
    }

    func syncCurrentDevice() async {
        guard let accessToken = currentSession?.accessToken else {
            return
        }

        isSyncingDevices = true
        defer { isSyncingDevices = false }

        do {
            let metadata = deviceMetadataProvider.currentDevice()
            let device = try await deviceClient.registerDevice(metadata, accessToken: accessToken)
            currentDevice = device
            registeredDevices = deduplicatedDevices(try await deviceClient.listDevices(accessToken: accessToken))
            if !registeredDevices.contains(where: { $0.id == device.id }) {
                registeredDevices.insert(device, at: 0)
            }
            registeredDevices = deduplicatedDevices(registeredDevices)
            await fetchSavedActivityEvents()
            rebuildMonitoringSnapshots()
            rebuildHealthKPIs()
        } catch {
            errorMessage = "Device sync could not be completed. Your session is still active."
            logger.error("Device sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func refreshPermissionState(recordEvent: Bool = true) {
        cameraPermissionState = cameraPermissionService.currentState()
        rebuildMonitoringSnapshots()
        rebuildHealthKPIs()

        guard recordEvent else {
            return
        }

        let event = SecurityActivityEvent(
            kind: .permissionStatus,
            title: "Camera permission checked",
            detail: cameraPermissionState.detail,
            status: cameraPermissionState.monitoringStatus,
            observedApplicationName: "CamGuard iOS",
            observedBundleIdentifier: Bundle.main.bundleIdentifier,
            sourceDeviceName: currentDevice?.displayName ?? UIDevice.current.name,
            sourceDeviceType: currentDevice?.deviceTypeKey ?? "ios",
            sourceDeviceOS: currentDevice?.subtitle ?? "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            actionSummary: "Permission status recorded"
        )
        recordActivity(event, shouldSync: true)
    }

    func requestCameraPermission() async {
        cameraPermissionState = await cameraPermissionService.requestAccess()
        rebuildMonitoringSnapshots()
        rebuildHealthKPIs()
        let event = SecurityActivityEvent(
            kind: .permissionStatus,
            title: "Camera permission \(cameraPermissionState.title.lowercased())",
            detail: cameraPermissionState.detail,
            status: cameraPermissionState.monitoringStatus,
            observedApplicationName: "CamGuard iOS",
            observedBundleIdentifier: Bundle.main.bundleIdentifier,
            sourceDeviceName: currentDevice?.displayName ?? UIDevice.current.name,
            sourceDeviceType: currentDevice?.deviceTypeKey ?? "ios",
            sourceDeviceOS: currentDevice?.subtitle ?? "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            actionSummary: "Permission request completed"
        )
        recordActivity(event, shouldSync: true)
    }

    func startCameraSafetyTest() async {
        do {
            let snapshot = try await cameraSessionService.startSafetyTest()
            cameraPermissionState = snapshot.permissionState
            isCameraTestRunning = snapshot.isRunning
            cameraTestStartedAt = snapshot.startedAt
            rebuildMonitoringSnapshots()
            rebuildHealthKPIs()
            let event = SecurityActivityEvent(
                kind: .cameraStatus,
                title: "In-app camera safety test started",
                detail: "CamGuard opened its own camera session to verify permission and event reporting. No images or video are stored or uploaded.",
                status: .normal,
                observedApplicationName: "CamGuard iOS",
                observedBundleIdentifier: Bundle.main.bundleIdentifier,
                sourceDeviceName: currentDevice?.displayName ?? UIDevice.current.name,
                sourceDeviceType: currentDevice?.deviceTypeKey ?? "ios",
                sourceDeviceOS: currentDevice?.subtitle ?? "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
                actionSummary: "In-app safety test started"
            )
            recordActivity(event, shouldSync: true)
        } catch {
            errorMessage = error.localizedDescription
            refreshPermissionState(recordEvent: true)
        }
    }

    func stopCameraSafetyTest() async {
        let startedAt = cameraTestStartedAt
        let snapshot = await cameraSessionService.stopSafetyTest()
        cameraPermissionState = snapshot.permissionState
        isCameraTestRunning = snapshot.isRunning
        cameraTestStartedAt = nil
        rebuildMonitoringSnapshots()
        rebuildHealthKPIs()

        let duration = startedAt.map { max(0, Date().timeIntervalSince($0)) }
        let detail = duration.map {
            String(format: "The in-app camera safety test ended after %.1f seconds. Metadata only was retained.", $0)
        } ?? "The in-app camera safety test ended. Metadata only was retained."
        let event = SecurityActivityEvent(
            kind: .cameraStatus,
            title: "In-app camera safety test ended",
            detail: detail,
            status: .normal,
            observedApplicationName: "CamGuard iOS",
            observedBundleIdentifier: Bundle.main.bundleIdentifier,
            sourceDeviceName: currentDevice?.displayName ?? UIDevice.current.name,
            sourceDeviceType: currentDevice?.deviceTypeKey ?? "ios",
            sourceDeviceOS: currentDevice?.subtitle ?? "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            actionSummary: "In-app safety test stopped"
        )
        recordActivity(event, durationSeconds: duration, shouldSync: true)
    }

    func refreshSavedActivityNow() async {
        await fetchSavedActivityEvents()
    }

    func openCameraPrivacySettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(settingsURL)
    }

    func exportReport(for eventID: UUID) async -> URL? {
        guard let event = activityEvents.first(where: { $0.id == eventID }) else {
            return nil
        }

        return await reportGenerator.exportActivityReport(
            event: event,
            deviceName: currentDevice?.displayName ?? UIDevice.current.name,
            backendState: backendConnectionState,
            permissionState: cameraPermissionState,
            payload: lastMetadataPayload?.clientEventId == event.id ? lastMetadataPayload : nil
        )
    }

    func exportHealthReport() async -> URL? {
        await reportGenerator.exportHealthReport(
            user: currentUser,
            device: currentDevice,
            devices: registeredDevices,
            snapshots: monitoringSnapshots,
            backendState: backendConnectionState,
            permissionState: cameraPermissionState
        )
    }

    private func restorePersistedSession(from persistence: SessionPersistenceService) {
        let user = persistence.loadUser()
        let session = persistence.loadSession()
        if let user, let session {
            self.currentUser = user
            self.currentSession = session
        } else {
            self.currentUser = nil
            self.currentSession = nil
            persistence.clearUser()
            persistence.clearSession()
        }
    }

    private func configureCameraSession() {
        cameraSessionService.onSnapshot = { [weak self] snapshot in
            self?.cameraPermissionState = snapshot.permissionState
            self?.isCameraTestRunning = snapshot.isRunning
            self?.cameraTestStartedAt = snapshot.startedAt
            self?.rebuildMonitoringSnapshots()
        }
    }

    private func startSavedEventRefresh() {
        guard savedEventRefreshTask == nil else {
            return
        }

        savedEventRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { break }
                await self?.fetchSavedActivityEvents()
            }
        }
    }

    private func recordActivity(
        _ event: SecurityActivityEvent,
        durationSeconds: Double? = nil,
        shouldSync: Bool
    ) {
        activityEvents.insert(event, at: 0)
        if activityEvents.count > 100 {
            activityEvents.removeLast(activityEvents.count - 100)
        }

        guard shouldSync else {
            return
        }

        Task {
            await saveActivityEvent(event, durationSeconds: durationSeconds)
        }
    }

    private func recordPrivacyBoundary() {
        let event = SecurityActivityEvent(
            kind: .privacy,
            title: "iOS privacy boundary active",
            detail: "iOS does not allow CamGuard to monitor camera use by other apps. This app reports permission checks, in-app camera tests, device sync, and backend history only.",
            status: .normal,
            observedApplicationName: "CamGuard iOS",
            observedBundleIdentifier: Bundle.main.bundleIdentifier,
            sourceDeviceName: currentDevice?.displayName ?? UIDevice.current.name,
            sourceDeviceType: currentDevice?.deviceTypeKey ?? "ios",
            sourceDeviceOS: currentDevice?.subtitle ?? "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            actionSummary: "Privacy boundary shown",
            isSaved: true
        )
        activityEvents = [event]
    }

    private func saveActivityEvent(_ event: SecurityActivityEvent, durationSeconds: Double?) async {
        guard let accessToken = currentSession?.accessToken, let currentDevice else {
            return
        }

        do {
            let request = CameraEventSyncRequest(
                clientEventId: event.id,
                deviceId: currentDevice.id,
                eventType: event.kind == .permissionStatus ? "permission_change" : "camera_session",
                cameraStatus: cameraStatus(for: event),
                permissionStatus: cameraPermissionState.rawValue == "notDetermined" ? "not_determined" : cameraPermissionState.rawValue,
                occurredAt: event.occurredAt,
                collectedAt: Date(),
                application: CameraEventApplication(
                    displayName: "CamGuard iOS",
                    bundleIdentifier: Bundle.main.bundleIdentifier,
                    processId: nil,
                    signingTeamId: nil,
                    isTrusted: true,
                    isKnown: true
                ),
                durationSeconds: durationSeconds,
                activationCountRecentWindow: recentCameraActivationCount(),
                isBackgroundAccess: false,
                isRepeatedShortActivation: false,
                networkUploadAfterCamera: false,
                notes: event.detail
            )
            lastMetadataPayload = request
            let response = try await eventClient.saveCameraEvent(request, accessToken: accessToken)
            markActivityEvent(event.id, isSaved: true, saveError: nil, score: response.score)
        } catch {
            markActivityEvent(event.id, isSaved: false, saveError: "Not saved", score: nil)
            logger.error("Failed to save iOS camera activity event: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fetchSavedActivityEvents() async {
        guard let accessToken = currentSession?.accessToken else {
            return
        }

        do {
            let response = try await eventClient.fetchCameraEvents(accessToken: accessToken)
            let fetchedEvents = response.events.map(historyEvent)
            var mergedEvents = activityEvents
            for event in fetchedEvents where !mergedEvents.contains(where: { $0.id == event.id }) {
                mergedEvents.append(event)
            }
            activityEvents = Array(
                mergedEvents
                    .sorted { $0.occurredAt > $1.occurredAt }
                    .prefix(100)
            )
            rebuildHealthKPIs()
        } catch {
            logger.error("Failed to fetch saved camera events: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func deduplicatedDevices(_ devices: [RegisteredDevice]) -> [RegisteredDevice] {
        var seenKeys = Set<String>()
        return devices.filter { device in
            let key = [
                normalizedDeviceName(device.displayName),
                device.deviceTypeKey.lowercased(),
                device.osName.lowercased(),
                device.osVersion.lowercased(),
                (device.modelName ?? "").lowercased()
            ].joined(separator: "|")
            guard !seenKeys.contains(key) else {
                return false
            }
            seenKeys.insert(key)
            return true
        }
    }

    private func normalizedDeviceName(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"\s+\(\d+\)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func historyEvent(_ item: CameraEventHistoryItem) -> SecurityActivityEvent {
        SecurityActivityEvent(
            id: item.clientEventId,
            occurredAt: item.occurredAt,
            kind: item.cameraStatus == "permission_only" ? .permissionStatus : .cameraStatus,
            title: historyTitle(for: item.cameraStatus),
            detail: item.notes ?? "Saved camera activity event.",
            status: monitoringStatus(for: item.score?.threatLevel),
            observedApplicationName: item.applicationDisplayName,
            observedProcessID: item.observedProcessId.map { Int32($0) },
            observedBundleIdentifier: item.observedBundleIdentifier,
            sourceDeviceName: item.sourceDeviceName,
            sourceDeviceType: item.sourceDeviceType,
            sourceDeviceOS: item.sourceDeviceOs,
            actionSummary: actionSummary(for: item),
            isSaved: true,
            anomalyScore: item.score?.anomalyScore,
            contextualScore: item.score?.contextualScore,
            threatProbability: item.score?.threatProbability,
            threatLevel: item.score?.threatLevel
        )
    }

    private func actionSummary(for item: CameraEventHistoryItem) -> String {
        guard let action = item.protectionAction else {
            if item.score?.threatLevel == "critical" || item.score?.threatLevel == "suspicious" {
                return "Review required"
            }
            return "Recorded only"
        }

        let result = item.protectionResult ?? "pending"
        let confidence = item.protectionConfidence.map { " / \($0)" } ?? ""
        return "\(action) - \(result)\(confidence)"
    }

    private func historyTitle(for cameraStatus: String) -> String {
        switch cameraStatus {
        case "started", "active":
            return "Camera activity detected"
        case "ended":
            return "Camera activity ended"
        case "permission_only":
            return "Camera permission event"
        default:
            return "Camera activity"
        }
    }

    private func monitoringStatus(for threatLevel: String?) -> MonitoringStatus {
        switch threatLevel {
        case "critical":
            return .critical
        case "suspicious":
            return .suspicious
        default:
            return .normal
        }
    }

    private func cameraStatus(for event: SecurityActivityEvent) -> String {
        if event.kind == .permissionStatus {
            return "permission_only"
        }
        if event.title.localizedCaseInsensitiveContains("ended") {
            return "ended"
        }
        if event.title.localizedCaseInsensitiveContains("started") {
            return "started"
        }
        return isCameraTestRunning ? "active" : "unknown"
    }

    private func recentCameraActivationCount() -> Int {
        let cutoff = Date().addingTimeInterval(-600)
        return activityEvents.filter { event in
            event.occurredAt >= cutoff
                && event.kind == .cameraStatus
                && event.title.localizedCaseInsensitiveContains("started")
        }.count
    }

    private func markActivityEvent(_ id: UUID, isSaved: Bool, saveError: String?, score: CameraEventScore?) {
        guard let index = activityEvents.firstIndex(where: { $0.id == id }) else {
            return
        }
        activityEvents[index].isSaved = isSaved
        activityEvents[index].saveError = saveError
        if let score {
            activityEvents[index].anomalyScore = score.anomalyScore
            activityEvents[index].contextualScore = score.contextualScore
            activityEvents[index].threatProbability = score.threatProbability
            activityEvents[index].threatLevel = score.threatLevel
        }
        rebuildHealthKPIs()
    }

    private func rebuildMonitoringSnapshots() {
        monitoringSnapshots = [
            MonitoringSnapshot(
                title: "Camera Status",
                value: isCameraTestRunning ? "Active" : "Idle",
                detail: isCameraTestRunning
                    ? "CamGuard's own in-app camera safety test is running."
                    : "No CamGuard in-app camera session is running.",
                status: isCameraTestRunning ? .normal : .normal
            ),
            MonitoringSnapshot(
                title: "Permission",
                value: cameraPermissionState.title,
                detail: cameraPermissionState.detail,
                status: cameraPermissionState.monitoringStatus
            ),
            MonitoringSnapshot(
                title: "Device Sync",
                value: currentDevice == nil ? "Pending" : "Enrolled",
                detail: currentDevice == nil
                    ? "This iPhone or iPad has not completed device sync yet."
                    : "This device is linked to your CamGuard account.",
                status: currentDevice == nil ? .suspicious : .normal
            )
        ]
    }

    private func rebuildHealthKPIs() {
        let now = Date()
        let recentEvents = activityEvents.filter { now.timeIntervalSince($0.occurredAt) <= 86_400 }
        let riskyEvents = activityEvents.filter { $0.status == .suspicious || $0.status == .critical }
        let criticalEvents = activityEvents.filter { $0.status == .critical }
        let actionedEvents = activityEvents.filter { ($0.actionSummary ?? "").localizedCaseInsensitiveContains("recorded only") == false }
        let savedRatio = activityEvents.isEmpty
            ? 1
            : Double(activityEvents.filter(\.isSaved).count) / Double(activityEvents.count)

        healthKPIs = [
            HealthKPI(
                title: "Device Registry",
                value: "\(registeredDevices.count)",
                detail: "From `devices`; duplicates collapsed by normalized identity.",
                status: currentDevice == nil ? .suspicious : .normal
            ),
            HealthKPI(
                title: "24h Events",
                value: "\(recentEvents.count)",
                detail: "From `camera_events`; recent metadata-only activity.",
                status: .normal
            ),
            HealthKPI(
                title: "Risk Mix",
                value: "\(criticalEvents.count) critical",
                detail: "\(riskyEvents.count) suspicious/critical events from `threat_scores`.",
                status: criticalEvents.isEmpty ? (riskyEvents.isEmpty ? .normal : .suspicious) : .critical
            ),
            HealthKPI(
                title: "Action Coverage",
                value: "\(actionedEvents.count)",
                detail: "Visible user/protection actions from `protection_actions` or local review state.",
                status: riskyEvents.isEmpty || actionedEvents.count >= riskyEvents.count ? .normal : .suspicious
            ),
            HealthKPI(
                title: "Save Health",
                value: "\(Int(savedRatio * 100))%",
                detail: "Saved camera metadata events versus local pending events.",
                status: savedRatio >= 0.9 ? .normal : .suspicious
            )
        ]
    }

    private func persistAuthenticatedResponse(_ response: AuthResponseDTO) throws {
        guard let session = response.session else {
            throw AuthAPIError.serverMessage("Authentication succeeded, but no session was returned. Check email confirmation settings.")
        }

        let user = AppUser(
            id: response.user.id,
            email: response.user.email ?? "",
            displayName: response.user.displayName ?? "CamGuard User",
            signedInAt: Date()
        )
        let authSession = AuthSession(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            tokenType: session.tokenType,
            expiresIn: session.expiresIn,
            expiresAt: session.expiresAt
        )

        currentUser = user
        currentSession = authSession
        persistence.saveUser(user)
        persistence.saveSession(authSession)
        errorMessage = nil
    }

    private func validateAuthInput(
        email: String,
        password: String,
        requireDisplayName: Bool,
        displayName: String?
    ) -> Bool {
        guard email.contains("@"), email.contains(".") else {
            errorMessage = "Enter a valid email address."
            return false
        }

        guard password.count >= 8 else {
            errorMessage = "Password must be at least 8 characters."
            return false
        }

        if requireDisplayName, (displayName ?? "").isEmpty {
            errorMessage = "Enter a display name to create your account."
            return false
        }

        return true
    }
}
