import Foundation
import Combine
import AVFoundation
import os

enum AppTab: String, CaseIterable, Identifiable {
    case overview
    case activity
    case devices
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .activity:
            return "Activity"
        case .devices:
            return "Devices"
        case .settings:
            return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            return "shield.lefthalf.filled"
        case .activity:
            return "waveform.path.ecg"
        case .devices:
            return "desktopcomputer"
        case .settings:
            return "gearshape"
        }
    }
}

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
    @Published var selectedTab: AppTab {
        didSet {
            persistence.saveLastSelectedTab(selectedTab)
        }
    }
    @Published var errorMessage: String?
    @Published var monitoringSnapshots: [MonitoringSnapshot] = MonitoringSnapshot.sample
    @Published private(set) var healthKPIs: [HealthKPI] = []

    private let persistence: SessionPersistenceService
    private let authClient: AuthAPIClient
    private let deviceClient: DeviceAPIClient
    private let eventClient: EventAPIClient
    private let protectionClient: ProtectionAPIClient
    private let deviceMetadataProvider: LocalDeviceMetadataProvider
    private let cameraMonitor: CameraMonitorService
    private let cameraProtectionService: CameraProtectionService
    private let reportGenerator: SecurityReportGenerator
    private let simulatorLoopbackHintService = SimulatorLoopbackHintService()
    private let logger = Logger(subsystem: "CamGuardMac", category: "AppSession")
    private var latestCameraSnapshot: CameraMonitorSnapshot?
    private var activeCameraSessionStartedAt: Date?
    private var recentShortCameraActivationEnds: [Date] = []
    private var eventDurations: [UUID: Double] = [:]
    private var eventActivationCounts: [UUID: Int] = [:]
    private var eventRepeatedShortFlags: [UUID: Bool] = [:]
    private var stoppingEventIDs: Set<UUID> = []
    private var savedEventRefreshTask: Task<Void, Never>?
    private var retryingPendingEventIDs: Set<UUID> = []
    private let shortCameraActivationLimit: TimeInterval = 5
    private let repeatedShortActivationWindow: TimeInterval = 600
    private let repeatedShortActivationThreshold = 3
    /// Website host seen when camera session started (ended events from the monitor often omit host).
    private var activeCameraSessionWebsiteHost: String?
    private var activeCameraSessionWebsiteURL: String?
    private var activeCameraSessionApplicationName: String?
    private var activeCameraSessionProcessID: Int32?
    private var activeCameraSessionBundleIdentifier: String?
    /// (camera_session_start, websiteHost) for browser correlation (localhost simulator + camguard:// callback).
    private var endedSessionByEventId: [UUID: (Date, String?)] = [:]
    private var networkPostCorrelationSignals: [(at: Date, host: String)] = []
    private let networkAfterCameraWindow: TimeInterval = 30
    private let networkCorrelationSignalRetention: TimeInterval = 600

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
        self.protectionClient = ProtectionAPIClient()
        self.deviceMetadataProvider = LocalDeviceMetadataProvider()
        self.cameraMonitor = CameraMonitorService()
        self.cameraProtectionService = CameraProtectionService()
        self.reportGenerator = SecurityReportGenerator()
        self.selectedTab = persistence.loadLastSelectedTab()
        configureCameraMonitor()
        restorePersistedSession(from: persistence)
        rebuildHealthKPIs()
        if isSignedIn {
            startMonitoring()
        }
    }

    init(
        persistence: SessionPersistenceService,
        authClient: AuthAPIClient,
        deviceClient: DeviceAPIClient,
        eventClient: EventAPIClient,
        protectionClient: ProtectionAPIClient,
        deviceMetadataProvider: LocalDeviceMetadataProvider,
        cameraMonitor: CameraMonitorService,
        cameraProtectionService: CameraProtectionService,
        reportGenerator: SecurityReportGenerator
    ) {
        self.persistence = persistence
        self.authClient = authClient
        self.deviceClient = deviceClient
        self.eventClient = eventClient
        self.protectionClient = protectionClient
        self.deviceMetadataProvider = deviceMetadataProvider
        self.cameraMonitor = cameraMonitor
        self.cameraProtectionService = cameraProtectionService
        self.reportGenerator = reportGenerator
        self.selectedTab = persistence.loadLastSelectedTab()
        configureCameraMonitor()
        restorePersistedSession(from: persistence)
        rebuildHealthKPIs()
        if isSignedIn {
            startMonitoring()
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
            startMonitoring()
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
                logger.info("Created Supabase account without session for \(normalizedEmail, privacy: .private)")
            } else {
                try persistAuthenticatedResponse(response)
                await syncCurrentDevice()
                startMonitoring()
                logger.info("Created Supabase-backed account through CamGuard API for \(normalizedEmail, privacy: .private)")
            }
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Backend sign up failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func signOut() async {
        logger.info("Signing out backend-backed macOS session.")
        let accessToken = currentSession?.accessToken

        if let accessToken {
            do {
                try await authClient.signOut(accessToken: accessToken)
            } catch {
                logger.error("Backend sign out failed, clearing local session anyway: \(error.localizedDescription, privacy: .public)")
            }
        }

        currentUser = nil
        currentSession = nil
        currentDevice = nil
        registeredDevices = []
        activityEvents = []
        stopMonitoring()
        selectedTab = .overview
        errorMessage = nil
        rebuildHealthKPIs()
        persistence.clearUser()
        persistence.clearSession()
        persistence.saveLastSelectedTab(.overview)
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
            logger.info("Requested confirmation resend for \(normalizedEmail, privacy: .private)")
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Confirmation resend failed: \(error.localizedDescription, privacy: .public)")
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
            backendConnectionState = .disconnected(message: "Cloud sync is temporarily unavailable. Monitoring on this Mac remains active.")
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
            startMonitoring()
            logger.info("Validated restored Supabase session with backend.")
        } catch {
            logger.warning("Restored session validation failed; clearing local session.")
            currentUser = nil
            currentSession = nil
            currentDevice = nil
            registeredDevices = []
            activityEvents = []
            stopMonitoring()
            persistence.clearUser()
            persistence.clearSession()
            errorMessage = "Your session expired. Please sign in again."
        }
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
            registeredDevices = try await deviceClient.listDevices(accessToken: accessToken)
            if !registeredDevices.contains(where: { $0.id == device.id }) {
                registeredDevices.insert(device, at: 0)
            }
            retryPendingActivityEvents()
            await fetchSavedActivityEvents()
            rebuildMonitoringSnapshots()
            rebuildHealthKPIs()
            logger.info("Registered current Mac with CamGuard backend.")
        } catch {
            errorMessage = "Device sync could not be completed. Your session is still active."
            logger.error("Device sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func startMonitoring() {
        cameraMonitor.start()
        simulatorLoopbackHintService.start { [weak self] host in
            Task { @MainActor in
                self?.recordSimulatorNetworkHint(host: host)
            }
        }
        startSavedEventRefresh()
        rebuildMonitoringSnapshots()
    }

    func stopMonitoring() {
        simulatorLoopbackHintService.stop()
        cameraMonitor.stop()
        savedEventRefreshTask?.cancel()
        savedEventRefreshTask = nil
        latestCameraSnapshot = nil
        activeCameraSessionStartedAt = nil
        activeCameraSessionWebsiteHost = nil
        activeCameraSessionWebsiteURL = nil
        activeCameraSessionApplicationName = nil
        activeCameraSessionProcessID = nil
        activeCameraSessionBundleIdentifier = nil
        recentShortCameraActivationEnds = []
        endedSessionByEventId = [:]
        networkPostCorrelationSignals = []
        monitoringSnapshots = MonitoringSnapshot.sample
        rebuildHealthKPIs()
    }

    /// Records a simulated “network after camera” hint from the Web Attack Simulator (loopback HTTP or `camguard://`).
    func recordSimulatorNetworkHint(host: String) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalized = AppSessionStore.normalizeWebsiteHost(trimmed)
        let now = Date()
        networkPostCorrelationSignals.append((at: now, host: normalized))
        networkPostCorrelationSignals.removeAll { now.timeIntervalSince($0.at) > networkCorrelationSignalRetention }
        logger.info("Simulator network hint recorded for host \(normalized, privacy: .public).")
    }

    /// `camguard://` fallback when the loopback hint server is unavailable (Safari may prompt to open the app).
    func handleIncomingSimulatorURL(_ url: URL) {
        guard url.scheme?.lowercased() == "camguard" else { return }
        let hostFromQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "host" })?
            .value
        let raw = (hostFromQuery ?? url.host) ?? ""
        recordSimulatorNetworkHint(host: raw)
    }

    func refreshSavedActivityNow() async {
        await fetchSavedActivityEvents()
    }

    private func startSavedEventRefresh() {
        guard savedEventRefreshTask == nil else {
            return
        }

        savedEventRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await self?.fetchSavedActivityEvents()
            }
        }
    }

    private func configureCameraMonitor() {
        cameraMonitor.onEvent = { [weak self] event in
            self?.recordActivity(event)
        }
        cameraMonitor.onSnapshot = { [weak self] snapshot in
            self?.latestCameraSnapshot = snapshot
            self?.rebuildMonitoringSnapshots()
        }
    }

    private func recordActivity(_ event: SecurityActivityEvent) {
        let enrichedEvent = eventWithCameraPatternContext(event)
        activityEvents.insert(enrichedEvent, at: 0)
        if activityEvents.count > 100 {
            activityEvents.removeLast(activityEvents.count - 100)
        }
        rebuildHealthKPIs()
        Task {
            await saveActivityEvent(enrichedEvent)
        }
    }

    private func eventWithCameraPatternContext(_ event: SecurityActivityEvent) -> SecurityActivityEvent {
        guard event.kind == .cameraStatus else {
            return event
        }

        if event.title.localizedCaseInsensitiveContains("detected") {
            activeCameraSessionStartedAt = event.occurredAt
            activeCameraSessionWebsiteHost = event.observedWebsiteHost
            activeCameraSessionWebsiteURL = event.observedWebsiteURL
            activeCameraSessionApplicationName = event.observedApplicationName
            activeCameraSessionProcessID = event.observedProcessID
            activeCameraSessionBundleIdentifier = event.observedBundleIdentifier
            return event
        }

        guard event.title.localizedCaseInsensitiveContains("ended") else {
            return event
        }

        let sessionStart = activeCameraSessionStartedAt
        let hostForSession = event.observedWebsiteHost ?? activeCameraSessionWebsiteHost
        let urlForSession = event.observedWebsiteURL ?? activeCameraSessionWebsiteURL
        let appForSession = event.observedApplicationName ?? activeCameraSessionApplicationName
        let processForSession = event.observedProcessID ?? activeCameraSessionProcessID
        let bundleForSession = event.observedBundleIdentifier ?? activeCameraSessionBundleIdentifier
        let duration = sessionStart.map { max(0, event.occurredAt.timeIntervalSince($0)) }
        activeCameraSessionStartedAt = nil
        activeCameraSessionWebsiteHost = nil
        activeCameraSessionWebsiteURL = nil
        activeCameraSessionApplicationName = nil
        activeCameraSessionProcessID = nil
        activeCameraSessionBundleIdentifier = nil
        if let start = sessionStart {
            endedSessionByEventId[event.id] = (start, hostForSession)
        }
        if let duration {
            eventDurations[event.id] = duration
            if duration < shortCameraActivationLimit {
                recentShortCameraActivationEnds.append(event.occurredAt)
            }
        }

        pruneRecentShortCameraActivations(relativeTo: event.occurredAt)
        let recentShortCount = recentShortCameraActivationEnds.count
        let isRepeatedShortActivation = recentShortCount >= repeatedShortActivationThreshold
        eventActivationCounts[event.id] = recentShortCount
        eventRepeatedShortFlags[event.id] = isRepeatedShortActivation

        guard isRepeatedShortActivation else {
            guard appForSession != nil || processForSession != nil || bundleForSession != nil || urlForSession != nil || hostForSession != nil else {
                return event
            }
            return SecurityActivityEvent(
                id: event.id,
                occurredAt: event.occurredAt,
                kind: event.kind,
                title: event.title,
                detail: event.detail,
                status: event.status,
                observedApplicationName: appForSession,
                observedProcessID: processForSession,
                observedBundleIdentifier: bundleForSession,
                observedWebsiteURL: urlForSession,
                observedWebsiteHost: hostForSession,
                isSaved: event.isSaved,
                saveError: event.saveError,
                anomalyScore: event.anomalyScore,
                contextualScore: event.contextualScore,
                threatProbability: event.threatProbability,
                threatLevel: event.threatLevel,
                protectionDecision: event.protectionDecision,
                protectionResult: event.protectionResult,
                networkUploadAfterCamera: event.networkUploadAfterCamera
            )
        }

        logger.warning("Repeated short camera activation pattern detected.")
        let durationSummary = duration.map { String(format: "%.1f", $0) } ?? "unknown"
        return SecurityActivityEvent(
            id: event.id,
            occurredAt: event.occurredAt,
            kind: event.kind,
            title: "Repeated short camera activations",
            detail: "Camera opened \(recentShortCount) times for less than 5 seconds within 10 minutes. Last duration: \(durationSummary) seconds.",
            status: .suspicious,
            observedApplicationName: appForSession,
            observedProcessID: processForSession,
            observedBundleIdentifier: bundleForSession,
            observedWebsiteURL: urlForSession,
            observedWebsiteHost: hostForSession,
            isSaved: event.isSaved,
            saveError: event.saveError,
            anomalyScore: event.anomalyScore,
            contextualScore: event.contextualScore,
            threatProbability: event.threatProbability,
            threatLevel: event.threatLevel,
            protectionDecision: event.protectionDecision,
            protectionResult: event.protectionResult,
            networkUploadAfterCamera: event.networkUploadAfterCamera
        )
    }

    private static func normalizeWebsiteHost(_ host: String) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased() == "127.0.0.1" {
            return "localhost"
        }
        return trimmed.lowercased()
    }

    private static func hostsEqualForCorrelation(_ a: String, _ b: String) -> Bool {
        normalizeWebsiteHost(a) == normalizeWebsiteHost(b)
    }

    private func hasNetworkPostCorrelation(since start: Date, websiteHost: String?) -> Bool {
        guard let site = websiteHost, !site.isEmpty else { return false }
        let siteNorm = AppSessionStore.normalizeWebsiteHost(site)
        let end = start.addingTimeInterval(networkAfterCameraWindow)
        let now = Date()
        for signal in networkPostCorrelationSignals {
            if signal.at >= start, signal.at <= min(end, now),
               AppSessionStore.hostsEqualForCorrelation(signal.host, siteNorm) {
                return true
            }
        }
        return false
    }

    private func shouldConsiderNetworkAfterCameraEvent(_ event: SecurityActivityEvent) -> Bool {
        guard event.kind == .cameraStatus else { return false }
        return event.title.localizedCaseInsensitiveContains("ended")
            || event.title.localizedCaseInsensitiveContains("repeated")
    }

    private func takeNetworkUploadAfterCamera(for event: SecurityActivityEvent) -> Bool {
        guard shouldConsiderNetworkAfterCameraEvent(event) else { return false }
        guard let pair = endedSessionByEventId.removeValue(forKey: event.id) else { return false }
        return hasNetworkPostCorrelation(since: pair.0, websiteHost: pair.1)
    }

    private func pruneRecentShortCameraActivations(relativeTo date: Date = Date()) {
        let cutoff = date.addingTimeInterval(-repeatedShortActivationWindow)
        recentShortCameraActivationEnds.removeAll { $0 < cutoff }
    }

    private func saveActivityEvent(_ event: SecurityActivityEvent) async {
        guard let accessToken = currentSession?.accessToken, let currentDevice else {
            markActivityEvent(
                event.id,
                isSaved: false,
                saveError: "Waiting for device sync",
                score: nil,
                networkUploadAfterCamera: event.networkUploadAfterCamera
            )
            return
        }

        let networkUpload = takeNetworkUploadAfterCamera(for: event)
        do {
            let trustContext = TrustedCameraApplicationPolicy.context(
                for: event.observedApplicationName,
                websiteDomain: event.observedWebsiteHost
            )
            let recentActivationCount = eventActivationCounts[event.id] ?? recentCameraActivationCount()
            let repeatedShortActivation = eventRepeatedShortFlags[event.id] ?? false
            let request = CameraEventSyncRequest(
                clientEventId: event.id,
                deviceId: currentDevice.id,
                eventType: event.kind == .permissionStatus ? "permission_change" : "camera_session",
                cameraStatus: cameraStatus(for: event),
                permissionStatus: permissionStatusKey(),
                occurredAt: event.occurredAt,
                collectedAt: Date(),
                application: CameraEventApplication(
                    displayName: trustContext.displayName,
                    bundleIdentifier: event.observedBundleIdentifier,
                    processId: event.observedProcessID.map(Int.init),
                    signingTeamId: nil,
                    isTrusted: trustContext.isTrusted,
                    isKnown: trustContext.isKnown
                ),
                durationSeconds: eventDurations[event.id],
                activationCountRecentWindow: recentActivationCount,
                isBackgroundAccess: false,
                isRepeatedShortActivation: repeatedShortActivation && !trustContext.isTrusted,
                networkUploadAfterCamera: networkUpload,
                observedWebsiteUrl: event.observedWebsiteURL,
                observedWebsiteHost: event.observedWebsiteHost,
                notes: event.observedWebsiteURL.map { "\(event.detail) URL: \($0)" } ?? event.detail
            )
            let response = try await eventClient.saveCameraEvent(request, accessToken: accessToken)
            markActivityEvent(event.id, isSaved: true, saveError: nil, score: response.score, networkUploadAfterCamera: networkUpload)
        } catch {
            markActivityEvent(event.id, isSaved: false, saveError: "Not saved", score: nil, networkUploadAfterCamera: networkUpload)
            logger.error("Failed to save camera activity event: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func retryPendingActivityEvents() {
        guard currentSession?.accessToken != nil, currentDevice != nil else {
            return
        }

        let pendingEvents = activityEvents.filter { event in
            !event.isSaved && !retryingPendingEventIDs.contains(event.id)
        }
        for event in pendingEvents {
            retryingPendingEventIDs.insert(event.id)
            Task {
                await saveActivityEvent(event)
                retryingPendingEventIDs.remove(event.id)
            }
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
            for event in fetchedEvents {
                if let index = mergedEvents.firstIndex(where: { $0.id == event.id }) {
                    var updatedEvent = event
                    let existingResult = mergedEvents[index].protectionResult
                    let discardStaleWarning = shouldDiscardStaleWarningResult(existingResult, for: updatedEvent)
                    let replaceDecision = shouldReplaceLocalDecision(mergedEvents[index].protectionDecision, with: event)
                    updatedEvent.protectionDecision = discardStaleWarning
                        ? event.protectionDecision
                        : (replaceDecision ? event.protectionDecision : (mergedEvents[index].protectionDecision ?? event.protectionDecision))
                    updatedEvent.protectionResult = discardStaleWarning
                        ? event.protectionResult
                        : (existingResult ?? event.protectionResult)
                    updatedEvent.networkUploadAfterCamera = mergedEvents[index].networkUploadAfterCamera ?? event.networkUploadAfterCamera
                    mergedEvents[index] = updatedEvent
                } else {
                    mergedEvents.append(event)
                }
            }
            activityEvents = Array(
                mergedEvents
                    .sorted { $0.occurredAt > $1.occurredAt }
                    .prefix(100)
            )
            rebuildHealthKPIs()
            stopConfirmedCriticalEventsIfNeeded()
        } catch {
            logger.error("Failed to fetch saved camera events: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func historyEvent(_ item: CameraEventHistoryItem) -> SecurityActivityEvent {
        let websiteHost = item.observedWebsiteHost ?? websiteHost(from: item.notes)
        let trustContext = TrustedCameraApplicationPolicy.context(
            for: item.applicationDisplayName,
            websiteDomain: websiteHost
        )
        let level = displayStatus(
            backendThreatLevel: item.score?.threatLevel,
            trustContext: trustContext
        )
        var event = SecurityActivityEvent(
            id: item.clientEventId,
            occurredAt: item.occurredAt,
            kind: item.cameraStatus == "permission_only" ? .permissionStatus : .cameraStatus,
            title: historyTitle(for: item.cameraStatus),
            detail: item.notes ?? "Saved camera activity event.",
            status: level,
            observedApplicationName: item.applicationDisplayName,
            observedProcessID: item.observedProcessId.map { pid_t($0) },
            observedBundleIdentifier: item.observedBundleIdentifier,
            observedWebsiteURL: item.observedWebsiteUrl ?? websiteURL(from: item.notes),
            observedWebsiteHost: websiteHost,
            isSaved: true,
            saveError: nil,
            anomalyScore: item.score?.anomalyScore,
            contextualScore: item.score?.contextualScore,
            threatProbability: item.score?.threatProbability,
            threatLevel: item.score?.threatLevel,
            networkUploadAfterCamera: nil
        )
        if event.requiresProtectionControls {
            guard event.threatLevel != nil else {
                return event
            }
            event.protectionDecision = cameraProtectionService.evaluateProtectionAction(for: event)
        }
        return event
    }

    func trustSource(for eventID: UUID) async {
        guard let index = activityEvents.firstIndex(where: { $0.id == eventID }) else {
            return
        }

        let event = activityEvents[index]
        TrustedCameraApplicationPolicy.trustSource(named: event.trustSourceName)
        activityEvents[index].status = .normal
        activityEvents[index].protectionDecision = nil
        activityEvents[index].protectionResult = ProtectionResult(
            eventID: event.id,
            action: .warnOnly,
            success: true,
            status: "Trusted by user",
            detail: "\(event.trustSourceName) was marked as trusted by the user.",
            confidence: .confirmed,
            processID: event.observedProcessID,
            appName: event.trustSourceName,
            timestamp: Date(),
            reportPath: nil
        )
        await syncProtectionResult(activityEvents[index].protectionResult!)
        rebuildHealthKPIs()
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

    private func displayStatus(
        backendThreatLevel: String?,
        trustContext: CameraApplicationTrustContext
    ) -> MonitoringStatus {
        let backendStatus = monitoringStatus(for: backendThreatLevel)
        guard trustContext.isTrusted, backendStatus == .suspicious else {
            return backendStatus
        }
        return .normal
    }

    private func websiteURL(from notes: String?) -> String? {
        guard let notes,
              let range = notes.range(of: "URL: ") else {
            return nil
        }
        return String(notes[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func websiteHost(from notes: String?) -> String? {
        guard let url = websiteURL(from: notes) else {
            return nil
        }
        let prepared = url.contains("://") ? url : "https://\(url)"
        return URL(string: prepared)?.host?.replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
    }

    func stopApp(for eventID: UUID) async {
        guard !stoppingEventIDs.contains(eventID) else {
            logger.warning("Ignoring duplicate stop request for event \(eventID.uuidString, privacy: .public)")
            return
        }
        stoppingEventIDs.insert(eventID)
        defer {
            stoppingEventIDs.remove(eventID)
        }

        guard let event = activityEvents.first(where: { $0.id == eventID }) else {
            return
        }

        var decision = event.protectionDecision ?? cameraProtectionService.evaluateProtectionAction(for: event)
        updateProtectionDecision(eventID: eventID, decision: decision)

        if decision.action == .closeBrowserTab {
            guard let process = decision.suspectedProcess, process.processID > 0 else {
                let result = ProtectionResult.skipped(eventID: eventID, decision: decision, status: "Unable to identify browser")
                updateProtectionResult(eventID: eventID, result: result)
                await syncProtectionResult(result)
                return
            }

            let result = await cameraProtectionService.closeSuspiciousBrowserTab(event: event, process: process)
            updateProtectionResult(eventID: eventID, result: result)
            await syncProtectionResult(result)

            if !result.success {
                if isKnownBrowser(process) {
                    // Safety policy: never terminate the host browser as a fallback
                    // when a tab close fails. This prevents CamGuard from quitting
                    // Safari/Chrome/Edge/Arc and closing the user's other tabs.
                    let safeResult = ProtectionResult.skipped(
                        eventID: eventID,
                        decision: decision,
                        status: "Tab not closed — manual review"
                    )
                    updateProtectionResult(eventID: eventID, result: safeResult)
                    await syncProtectionResult(safeResult)
                    cameraProtectionService.openCameraPrivacySettings()
                } else {
                    var fallbackDecision = ProtectionDecision(
                        eventID: decision.eventID,
                        action: .terminateProcess,
                        confidence: decision.confidence,
                        suspectedProcess: process,
                        reasons: decision.reasons,
                        requiresConfirmation: decision.requiresConfirmation,
                        explanation: "The website tab could not be closed directly, so CamGuard will stop \(process.appName)."
                    )
                    updateProtectionDecision(eventID: eventID, decision: fallbackDecision)
                    if fallbackDecision.requiresConfirmation {
                        let confirmed = await cameraProtectionService.requestUserConfirmation(for: fallbackDecision)
                        guard confirmed else {
                            let cancelResult = ProtectionResult.skipped(eventID: eventID, decision: fallbackDecision, status: "Cancelled")
                            updateProtectionResult(eventID: eventID, result: cancelResult)
                            await syncProtectionResult(cancelResult)
                            return
                        }
                        fallbackDecision = ProtectionDecision(
                            eventID: fallbackDecision.eventID,
                            action: fallbackDecision.action,
                            confidence: fallbackDecision.confidence,
                            suspectedProcess: fallbackDecision.suspectedProcess,
                            reasons: fallbackDecision.reasons,
                            requiresConfirmation: false,
                            explanation: fallbackDecision.explanation
                        )
                    }
                    let fallbackResult = await cameraProtectionService.stopSuspiciousProcess(process, eventID: eventID, forceIfNeeded: shouldForceStopWithoutAdditionalConfirmation(process: process, decision: fallbackDecision))
                    updateProtectionResult(eventID: eventID, result: fallbackResult)
                    await syncProtectionResult(fallbackResult)
                }
            }
            return
        }

        guard decision.action == .terminateProcess else {
            if decision.action == .openPrivacySettings || decision.action == .requestManualReview {
                cameraProtectionService.openCameraPrivacySettings()
            }
            let result = ProtectionResult.skipped(eventID: eventID, decision: decision, status: "Manual review required")
            updateProtectionResult(eventID: eventID, result: result)
            await syncProtectionResult(result)
            return
        }

        if decision.requiresConfirmation {
            let confirmed = await cameraProtectionService.requestUserConfirmation(for: decision)
            guard confirmed else {
                let result = ProtectionResult.skipped(eventID: eventID, decision: decision, status: "Cancelled")
                updateProtectionResult(eventID: eventID, result: result)
                await syncProtectionResult(result)
                return
            }
        }

        guard let process = decision.suspectedProcess, process.processID > 0 else {
            let result = ProtectionResult.skipped(eventID: eventID, decision: decision, status: "Unable to identify process")
            updateProtectionResult(eventID: eventID, result: result)
            await syncProtectionResult(result)
            return
        }

        if decision.action == .warnOnly, process.isTrusted {
            decision = ProtectionDecision(
                eventID: decision.eventID,
                action: .terminateProcess,
                confidence: decision.confidence,
                suspectedProcess: process,
                reasons: decision.reasons,
                requiresConfirmation: true,
                explanation: "User confirmed stopping trusted app \(process.appName)."
            )
            updateProtectionDecision(eventID: eventID, decision: decision)
        }

        var result = await cameraProtectionService.stopSuspiciousProcess(process, eventID: eventID)
        if result.status == "User confirmation required" {
            if shouldForceStopWithoutAdditionalConfirmation(process: process, decision: decision) {
                result = await cameraProtectionService.stopSuspiciousProcess(process, eventID: eventID, forceIfNeeded: true)
            } else {
                let confirmed = await cameraProtectionService.requestUserConfirmation(for: decision)
                if confirmed {
                    result = await cameraProtectionService.stopSuspiciousProcess(process, eventID: eventID, forceIfNeeded: true)
                }
            }
        }

        cameraProtectionService.createProtectionAuditLog(event: event, result: result)
        updateProtectionResult(eventID: eventID, result: result)
        await syncProtectionResult(result)
    }

    func downloadReport(for eventID: UUID) async {
        guard let event = activityEvents.first(where: { $0.id == eventID }) else {
            return
        }

        let decision = event.protectionDecision ?? cameraProtectionService.evaluateProtectionAction(for: event)
        let url = await reportGenerator.exportPdfReport(
            event: event,
            decision: decision,
            result: event.protectionResult,
            deviceName: currentDevice?.displayName ?? "This Mac"
        )
        guard let url else {
            return
        }

        if var result = event.protectionResult {
            result = ProtectionResult(
                eventID: result.eventID,
                action: result.action,
                success: result.success,
                status: result.status,
                detail: result.detail,
                confidence: result.confidence,
                processID: result.processID,
                appName: result.appName,
                timestamp: result.timestamp,
                reportPath: url.path
            )
            updateProtectionResult(eventID: eventID, result: result)
            await syncProtectionResult(result)
        }
    }

    private func markActivityEvent(
        _ id: UUID,
        isSaved: Bool,
        saveError: String?,
        score: CameraEventScore?,
        networkUploadAfterCamera: Bool? = nil
    ) {
        guard let index = activityEvents.firstIndex(where: { $0.id == id }) else {
            return
        }
        activityEvents[index].isSaved = isSaved
        activityEvents[index].saveError = saveError
        if let networkUploadAfterCamera {
            activityEvents[index].networkUploadAfterCamera = networkUploadAfterCamera
        }
        if let score {
            activityEvents[index].anomalyScore = score.anomalyScore
            activityEvents[index].contextualScore = score.contextualScore
            activityEvents[index].threatProbability = score.threatProbability
            activityEvents[index].threatLevel = score.threatLevel
            let trustContext = TrustedCameraApplicationPolicy.context(
                for: activityEvents[index].observedApplicationName,
                websiteDomain: activityEvents[index].observedWebsiteHost
            )
            activityEvents[index].status = displayStatus(
                backendThreatLevel: score.threatLevel,
                trustContext: trustContext
            )
            if shouldDiscardStaleWarningResult(activityEvents[index].protectionResult, for: activityEvents[index]) {
                activityEvents[index].protectionResult = nil
                activityEvents[index].protectionDecision = nil
            }
        }
        if activityEvents[index].requiresProtectionControls, activityEvents[index].threatLevel != nil {
            activityEvents[index].protectionDecision = cameraProtectionService.evaluateProtectionAction(for: activityEvents[index])
        }
        rebuildHealthKPIs()
        stopConfirmedCriticalEventsIfNeeded()
    }

    private func shouldDiscardStaleWarningResult(
        _ result: ProtectionResult?,
        for event: SecurityActivityEvent
    ) -> Bool {
        guard let result,
              event.isWebsiteAttributed,
              event.status == .critical || event.threatLevel == "critical" else {
            return false
        }
        return result.action == .warnOnly || result.status.localizedCaseInsensitiveContains("warning")
    }

    private func shouldReplaceLocalDecision(
        _ decision: ProtectionDecision?,
        with authoritativeEvent: SecurityActivityEvent
    ) -> Bool {
        guard let decision else {
            return false
        }
        guard authoritativeEvent.threatLevel != nil,
              authoritativeEvent.requiresProtectionControls else {
            return false
        }
        if authoritativeEvent.status == .critical || authoritativeEvent.threatLevel == "critical" {
            return decision.action == .warnOnly || decision.action == .none
        }
        return false
    }

    func openCameraPrivacySettings() {
        cameraProtectionService.openCameraPrivacySettings()
    }

    private func stopConfirmedCriticalEventsIfNeeded() {
        let candidates = activityEvents.filter { event in
            event.protectionResult == nil
                && !stoppingEventIDs.contains(event.id)
                && shouldAutoStopConfirmedCriticalEvent(event)
        }

        for event in candidates {
            Task {
                await stopApp(for: event.id)
            }
        }
    }

    private func shouldAutoStopConfirmedCriticalEvent(_ event: SecurityActivityEvent) -> Bool {
        guard event.threatLevel == "critical" || event.status == .critical else {
            return false
        }

        let decision = event.protectionDecision ?? cameraProtectionService.evaluateProtectionAction(for: event)
        guard (decision.action == .terminateProcess || decision.action == .closeBrowserTab),
              decision.confidence == .confirmed,
              !decision.requiresConfirmation,
              let process = decision.suspectedProcess else {
            return false
        }

        return (decision.action == .closeBrowserTab || !process.isTrusted)
            && !process.isSystemCritical
            && !process.isCamGuard
            && process.processID > 0
    }

    private static let knownBrowserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser"
    ]

    private func isKnownBrowser(_ process: ProcessInfoModel) -> Bool {
        guard let bundleIdentifier = process.bundleIdentifier else {
            return false
        }
        return Self.knownBrowserBundleIDs.contains(bundleIdentifier)
    }

    private func shouldForceStopWithoutAdditionalConfirmation(
        process: ProcessInfoModel,
        decision: ProtectionDecision
    ) -> Bool {
        (decision.action == .terminateProcess || decision.action == .closeBrowserTab)
            && !decision.requiresConfirmation
            && !process.isTrusted
            && !process.isSystemCritical
            && !process.isCamGuard
            && process.processID > 0
    }

    private func updateProtectionDecision(eventID: UUID, decision: ProtectionDecision) {
        guard let index = activityEvents.firstIndex(where: { $0.id == eventID }) else {
            return
        }
        activityEvents[index].protectionDecision = decision
        rebuildHealthKPIs()
    }

    private func updateProtectionResult(eventID: UUID, result: ProtectionResult) {
        guard let index = activityEvents.firstIndex(where: { $0.id == eventID }) else {
            return
        }
        activityEvents[index].protectionResult = result
        rebuildHealthKPIs()
    }

    private func syncProtectionResult(_ result: ProtectionResult) async {
        guard let accessToken = currentSession?.accessToken else {
            return
        }

        do {
            try await protectionClient.syncProtectionAction(
                ProtectionActionSyncRequest(
                    eventId: result.eventID,
                    deviceId: currentDevice?.id,
                    appName: result.appName ?? "Unknown Application",
                    processId: result.processID.map(Int.init),
                    action: result.action.rawValue,
                    result: result.status,
                    confidence: result.confidence.rawValue,
                    timestamp: result.timestamp,
                    reportPath: result.reportPath
                ),
                accessToken: accessToken
            )
        } catch {
            logger.error("Failed to sync protection action: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func cameraStatus(for event: SecurityActivityEvent) -> String {
        if event.kind == .permissionStatus {
            return "permission_only"
        }
        if eventRepeatedShortFlags[event.id] == true {
            return "ended"
        }
        if event.title.localizedCaseInsensitiveContains("ended") {
            return "ended"
        }
        if event.title.localizedCaseInsensitiveContains("detected") {
            return "started"
        }
        return "unknown"
    }

    private func permissionStatusKey() -> String {
        guard let status = latestCameraSnapshot?.permissionStatus else {
            return "unknown"
        }
        switch status {
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

    private func recentCameraActivationCount() -> Int {
        let cutoff = Date().addingTimeInterval(-600)
        return activityEvents.filter { event in
            event.occurredAt >= cutoff
                && event.kind == .cameraStatus
                && event.title.localizedCaseInsensitiveContains("detected")
        }.count
    }

    private func rebuildMonitoringSnapshots() {
        let cameraSnapshot = latestCameraSnapshot
        let cameraInUse = cameraSnapshot?.isCameraInUse ?? false
        let permissionStatus = cameraSnapshot?.permissionStatus

        let permissionValue: String
        let permissionDetail: String
        let permissionMonitoringStatus: MonitoringStatus
        if let permissionStatus {
            switch permissionStatus {
            case .authorized:
                permissionValue = "Authorized"
                permissionDetail = "Camera permission checks are available."
                permissionMonitoringStatus = .normal
            case .denied, .restricted:
                permissionValue = "Restricted"
                permissionDetail = "Camera permission is denied or restricted."
                permissionMonitoringStatus = .suspicious
            case .notDetermined:
                permissionValue = "Not Requested"
                permissionDetail = "CamGuard is monitoring without capturing media."
                permissionMonitoringStatus = .normal
            @unknown default:
                permissionValue = "Unknown"
                permissionDetail = "macOS returned an unknown permission state."
                permissionMonitoringStatus = .suspicious
            }
        } else {
            permissionValue = "Checking"
            permissionDetail = "Camera permission status is being evaluated."
            permissionMonitoringStatus = .normal
        }

        monitoringSnapshots = [
            MonitoringSnapshot(
                title: "Camera Status",
                value: cameraInUse ? "Active" : "Idle",
                detail: cameraInUse ? "macOS reports camera use on this Mac." : "No active external camera session is currently reported.",
                status: cameraStatusLevel()
            ),
            MonitoringSnapshot(
                title: "Permission",
                value: permissionValue,
                detail: permissionDetail,
                status: permissionMonitoringStatus
            ),
            MonitoringSnapshot(
                title: "Device Sync",
                value: currentDevice == nil ? "Pending" : "Enrolled",
                detail: currentDevice == nil ? "This Mac has not completed device sync yet." : "This Mac is linked to your CamGuard account.",
                status: currentDevice == nil ? .suspicious : .normal
            )
        ]
        rebuildHealthKPIs()
    }

    private func rebuildHealthKPIs() {
        let now = Date()
        let recentEvents = activityEvents.filter { now.timeIntervalSince($0.occurredAt) <= 86_400 }
        let riskyEvents = activityEvents.filter { $0.status == .suspicious || $0.status == .critical }
        let criticalEvents = activityEvents.filter { $0.status == .critical }
        let actionedEvents = activityEvents.filter { event in
            event.protectionResult != nil
                || TrustedCameraApplicationPolicy.isUserTrustedSource(event.trustSourceName)
        }
        let savedRatio = activityEvents.isEmpty
            ? 1
            : Double(activityEvents.filter(\.isSaved).count) / Double(activityEvents.count)

        healthKPIs = [
            HealthKPI(
                title: "Device Registry",
                value: "\(registeredDevices.count)",
                detail: "From `devices`; this Mac plus linked clients.",
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
                detail: "User/protection actions from `protection_actions` or trusted-source decisions.",
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

    private func cameraStatusLevel() -> MonitoringStatus {
        guard latestCameraSnapshot?.isCameraInUse == true else {
            return .normal
        }
        return TrustedCameraApplicationPolicy.context(
            for: latestCameraSnapshot?.observedApplicationName,
            websiteDomain: latestCameraSnapshot?.browserContext?.host
        ).isTrusted ? .normal : .suspicious
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
            logger.warning("Rejected auth attempt because email validation failed.")
            return false
        }

        guard password.count >= 8 else {
            errorMessage = "Password must be at least 8 characters."
            logger.warning("Rejected auth attempt because password validation failed.")
            return false
        }

        if requireDisplayName, (displayName ?? "").isEmpty {
            errorMessage = "Enter a display name to create your account."
            logger.warning("Rejected sign up attempt because display name was empty.")
            return false
        }

        return true
    }
}
