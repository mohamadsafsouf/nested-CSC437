import SwiftUI

struct MonitoringDashboardView: View {
    @EnvironmentObject private var session: AppSessionStore
    @State private var appeared = false
    @State private var reportShareItem: ReportShareItem?

    var body: some View {
        TabView(selection: $session.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            header

                            content(for: tab)
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }
                        .frame(maxWidth: AppTheme.Layout.contentMaxWidth, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.top, 22)
                        .padding(.bottom, 32)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 18)
                    }
                    .scrollIndicators(.hidden)
                    .background(AppTheme.ColorToken.background.ignoresSafeArea())
                    .navigationBarTitleDisplayMode(.inline)
                }
                .tag(tab)
                .tabItem {
                    Label(tab.title, systemImage: tab.systemImage)
                }
            }
        }
        .tint(AppTheme.ColorToken.accent)
        .animation(.easeInOut(duration: 0.20), value: session.selectedTab)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
                appeared = true
            }
        }
        .sheet(item: $reportShareItem) { item in
            reportShareSheet(item)
        }
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .overview:
            overview
        case .activity:
            activityPanel
        case .devices:
            devicesPanel
        case .settings:
            settingsPanel
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.selectedTab.title)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ColorToken.textPrimary)

                    Text(headerSubtitle)
                        .foregroundStyle(AppTheme.ColorToken.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)
                backendStatusBadge
            }

            userChip
        }
    }

    private var userChip: some View {
        HStack(spacing: 12) {
            Text(session.currentUser?.initials ?? "CG")
                .font(.headline)
                .foregroundStyle(.black)
                .frame(width: 42, height: 42)
                .background(AppTheme.ColorToken.accent)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(session.currentUser?.displayName ?? "CamGuard")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ColorToken.textPrimary)
                Text(session.currentUser?.email ?? "Not signed in")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ColorToken.textSecondary)
            }

            Spacer()
        }
        .camGuardInsetCard()
    }

    private var backendStatusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(session.backendConnectionState.color)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.backendConnectionState.title)
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.ColorToken.textPrimary)
                Text(session.backendConnectionState.detail)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.ColorToken.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(AppTheme.ColorToken.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.ColorToken.border, lineWidth: 1)
        )
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 18) {
            healthKPIPanel

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                ForEach(Array(session.monitoringSnapshots.enumerated()), id: \.element.id) { index, snapshot in
                    statusCard(snapshot)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .animation(.spring(response: 0.48, dampingFraction: 0.86).delay(Double(index) * 0.05), value: session.monitoringSnapshots.count)
                }
            }

            cameraControlPanel
            privacyBoundaryPanel
            payloadPanel
        }
    }

    private var healthKPIPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Health KPIs")
                .font(.title2.bold())

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                ForEach(session.healthKPIs) { kpi in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(kpi.title)
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.ColorToken.textSecondary)
                            Spacer()
                            Circle()
                                .fill(kpi.status.color)
                                .frame(width: 8, height: 8)
                        }
                        Text(kpi.value)
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                        Text(kpi.detail)
                            .font(.caption)
                            .foregroundStyle(AppTheme.ColorToken.textSecondary)
                            .lineLimit(3)
                    }
                    .foregroundStyle(AppTheme.ColorToken.textPrimary)
                    .camGuardInsetCard()
                }
            }
        }
        .foregroundStyle(AppTheme.ColorToken.textPrimary)
        .camGuardPanel()
    }

    private var cameraControlPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("In-App Camera Safety Test")
                        .font(.title2.bold())
                    Text("Start a CamGuard-owned session to verify permission and event sync. This does not monitor other apps and does not store media.")
                        .foregroundStyle(AppTheme.ColorToken.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: session.isCameraTestRunning ? "record.circle.fill" : "camera.viewfinder")
                    .font(.title2)
                    .foregroundStyle(session.isCameraTestRunning ? AppTheme.ColorToken.accent : AppTheme.ColorToken.textSecondary)
                    .symbolEffect(.pulse, options: .repeating, value: session.isCameraTestRunning)
            }

            HStack(spacing: 12) {
                Button {
                    Task {
                        if session.isCameraTestRunning {
                            await session.stopCameraSafetyTest()
                        } else {
                            await session.startCameraSafetyTest()
                        }
                    }
                } label: {
                    Label(session.isCameraTestRunning ? "Stop Test" : "Start Test", systemImage: session.isCameraTestRunning ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(session.isCameraTestRunning ? AppTheme.ColorToken.warning : AppTheme.ColorToken.accent)

                Button {
                    Task {
                        await session.requestCameraPermission()
                    }
                } label: {
                    Label("Permission", systemImage: "hand.raised")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.ColorToken.cyan)
            }
        }
        .foregroundStyle(AppTheme.ColorToken.textPrimary)
        .camGuardPanel()
    }

    private var privacyBoundaryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("iOS Privacy Boundary", systemImage: "lock.shield")
                .font(.title2.bold())

            Text("iOS only lets CamGuard report permission checks and in-app tests. Other apps stay private.")
                .foregroundStyle(AppTheme.ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                transparencyPill("No media upload", systemImage: "photo.badge.exclamationmark")
                transparencyPill("Metadata only", systemImage: "list.bullet.rectangle")
            }
        }
        .foregroundStyle(AppTheme.ColorToken.textPrimary)
        .camGuardPanel()
    }

    private var payloadPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("What CamGuard Sends", systemImage: "doc.text.magnifyingglass")
                .font(.title2.bold())

            if let payload = session.lastMetadataPayload {
                metadataRow("Event type", payload.eventType)
                metadataRow("Camera status", payload.cameraStatus)
                metadataRow("Permission", payload.permissionStatus)
                metadataRow("Background access", payload.isBackgroundAccess ? "true" : "false")
                metadataRow("Network upload after camera", payload.networkUploadAfterCamera ? "true" : "false")
                metadataRow("Notes", payload.notes ?? "None")
            } else {
                Text("Start a permission check or safety test to see the exact metadata payload before and after sync.")
                    .foregroundStyle(AppTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(AppTheme.ColorToken.textPrimary)
        .camGuardPanel()
    }

    private var activityPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent Activity")
                        .font(.title2.bold())
                    Text("Readable event cards with status, save state, score, and report export.")
                        .foregroundStyle(AppTheme.ColorToken.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    Task {
                        session.refreshPermissionState()
                        await session.refreshSavedActivityNow()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            ForEach(session.activityEvents) { event in
                activityRow(event)
            }
        }
        .foregroundStyle(AppTheme.ColorToken.textPrimary)
        .camGuardPanel()
    }

    private var devicesPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Trusted Devices")
                        .font(.title2.bold())
                    Text(deviceSummary)
                        .foregroundStyle(AppTheme.ColorToken.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    Task {
                        await session.syncCurrentDevice()
                    }
                } label: {
                    Image(systemName: session.isSyncingDevices ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .symbolEffect(.rotate, options: .repeating, value: session.isSyncingDevices)
                }
                .buttonStyle(.bordered)
                .disabled(session.isSyncingDevices)
            }

            if session.registeredDevices.isEmpty {
                emptyDeviceState
            } else {
                deviceHealthPanel
                ForEach(session.registeredDevices) { device in
                    deviceRow(device)
                }
            }
        }
        .foregroundStyle(AppTheme.ColorToken.textPrimary)
        .camGuardPanel()
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                Text("Session")
                    .font(.title2.bold())
                Text("Signed in as \(session.currentUser?.email ?? "unknown"). Your secure session remains on this device until you sign out.")
                    .foregroundStyle(AppTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Service Health")
                    .font(.headline)
                Text(session.backendConnectionState.detail)
                    .foregroundStyle(AppTheme.ColorToken.textSecondary)
            }
            .camGuardInsetCard()

            VStack(alignment: .leading, spacing: 8) {
                Text("Device Privacy")
                    .font(.headline)
                Text("Camera media stays on device and is never uploaded. CamGuard iOS cannot inspect other apps, background camera use, system-wide process lists, or network uploads by other apps.")
                    .foregroundStyle(AppTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .camGuardInsetCard()

            Button {
                Task {
                    await session.checkBackendConnection()
                    await session.syncCurrentDevice()
                }
            } label: {
                Label("Refresh Health", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.ColorToken.cyan)

            Button {
                Task {
                    if let url = await session.exportHealthReport() {
                        reportShareItem = ReportShareItem(url: url, title: "CamGuard Health Report")
                    }
                }
            } label: {
                Label("Download Health Report", systemImage: "arrow.down.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.ColorToken.accent)

            Button {
                session.openCameraPrivacySettings()
            } label: {
                Label("Open iOS Camera Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.ColorToken.accent)

            Button(role: .destructive) {
                Task {
                    await session.signOut()
                }
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .foregroundStyle(AppTheme.ColorToken.textPrimary)
        .camGuardPanel()
    }

    private var headerSubtitle: String {
        switch session.selectedTab {
        case .overview:
            return "Your iPhone or iPad is enrolled for privacy-friendly camera permission checks and metadata-only reporting."
        case .activity:
            return "Review iOS-supported camera, permission, and service health events."
        case .devices:
            return "Manage trusted devices associated with your CamGuard account."
        case .settings:
            return "Control your session, reports, service health, and privacy preferences."
        }
    }

    private var deviceSummary: String {
        if let currentDevice = session.currentDevice {
            return "\(currentDevice.displayName) is enrolled and syncing securely."
        }
        if session.isSyncingDevices {
            return "Enrolling this iOS device with your account."
        }
        return "This iPhone or iPad will be enrolled automatically after service health completes."
    }

    private var emptyDeviceState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No devices synced yet")
                .font(.headline)
            Text("Keep the app open for a moment, or refresh to enroll this iPhone or iPad.")
                .foregroundStyle(AppTheme.ColorToken.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .camGuardInsetCard()
    }

    private var deviceHealthPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: deviceHealthStatus == .normal ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(deviceHealthStatus.color)
                .frame(width: 42, height: 42)
                .background(deviceHealthStatus.color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(deviceHealthStatus == .normal ? "Device health is good" : "Device health needs attention")
                    .font(.headline)
                Text(deviceHealthDetail)
                    .font(.callout)
                    .foregroundStyle(AppTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .camGuardInsetCard()
    }

    private func statusCard(_ snapshot: MonitoringSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(snapshot.title)
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(snapshot.status.color)
                    .frame(width: 10, height: 10)
                    .shadow(color: snapshot.status.color.opacity(0.6), radius: 8)
            }

            Text(snapshot.value)
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text(snapshot.detail)
                .font(.callout)
                .foregroundStyle(AppTheme.ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(AppTheme.ColorToken.textPrimary)
        .camGuardPanel()
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
    }

    private func activityRow(_ event: SecurityActivityEvent) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: event.kind.icon)
                    .font(.title3)
                    .foregroundStyle(event.status.color)
                    .frame(width: 42, height: 42)
                    .background(event.status.color.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 7) {
                    Text(event.title)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if !event.sourceName.isEmpty {
                        Label(event.sourceName, systemImage: "app.badge")
                            .font(.caption.bold())
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(AppTheme.ColorToken.panelElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 5) {
                    Text(event.status.title)
                        .font(.caption.bold())
                        .foregroundStyle(event.status.color)
                    Text(event.isSaved ? "Saved" : (event.saveError ?? "Saving"))
                        .font(.caption2.bold())
                        .foregroundStyle(event.isSaved ? AppTheme.ColorToken.accent : AppTheme.ColorToken.warning)
                    Text(event.timeSummary)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.ColorToken.textSecondary)
                }
            }

            Text(event.detail)
                .font(.callout)
                .lineSpacing(2)
                .foregroundStyle(AppTheme.ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                activityMetaRow("Source Device", event.sourceDeviceSummary, systemImage: "display.and.arrow.down")
                activityMetaRow("Action", event.actionSummary ?? "Recorded only", systemImage: "shield.lefthalf.filled")
            }

            HStack(spacing: 10) {
                if let probability = event.threatProbability {
                    Label("Probability \(Int(probability * 100))%", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.caption.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(event.status.color.opacity(0.14))
                        .clipShape(Capsule())
                    .foregroundStyle(event.status.color)
                }

                Spacer()

                Button {
                    Task {
                        if let url = await session.exportReport(for: event.id) {
                            reportShareItem = ReportShareItem(url: url, title: "CamGuard Activity Report")
                        }
                    }
                } label: {
                    Label("Report", systemImage: "arrow.down.doc")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(AppTheme.ColorToken.cyan)
            }
        }
        .camGuardInsetCard()
    }

    private func activityMetaRow(_ title: String, _ value: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.bold())
                .foregroundStyle(AppTheme.ColorToken.cyan)
                .frame(width: 18)
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(AppTheme.ColorToken.textSecondary)
            Text(value)
                .font(.caption)
                .foregroundStyle(AppTheme.ColorToken.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    private func deviceRow(_ device: RegisteredDevice) -> some View {
        HStack(spacing: 14) {
            Image(systemName: deviceIcon(for: device))
                .font(.title2)
                .foregroundStyle(AppTheme.ColorToken.accent)
                .frame(width: 38, height: 38)
                .background(AppTheme.ColorToken.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(device.displayName)
                    .font(.headline)
                Text("\(device.subtitle) - \(device.lastSeenSummary)")
                    .font(.callout)
                    .foregroundStyle(AppTheme.ColorToken.textSecondary)
            }

            Spacer()

            if device.id == session.currentDevice?.id {
                Text("This Device")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.ColorToken.accent.opacity(0.18))
                    .clipShape(Capsule())
            }
        }
        .camGuardInsetCard()
    }

    private func transparencyPill(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppTheme.ColorToken.panelElevated.opacity(0.82))
            .clipShape(Capsule())
    }

    private func metadataRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(AppTheme.ColorToken.textSecondary)
                .frame(width: 122, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(AppTheme.ColorToken.textPrimary)
                .textSelection(.enabled)
            Spacer()
        }
        .camGuardInsetCard()
    }

    private var deviceHealthStatus: MonitoringStatus {
        if session.currentDevice == nil {
            return .suspicious
        }
        if case .disconnected = session.backendConnectionState {
            return .suspicious
        }
        return .normal
    }

    private var deviceHealthDetail: String {
        if session.currentDevice == nil {
            return "This iOS device is not enrolled yet."
        }
        return "\(session.registeredDevices.count) trusted device\(session.registeredDevices.count == 1 ? "" : "s") visible. No duplicate entries are shown."
    }

    private func deviceIcon(for device: RegisteredDevice) -> String {
        switch device.deviceTypeKey {
        case "ipad":
            return "ipad"
        case "ios":
            return "iphone"
        case "macos":
            return "desktopcomputer"
        default:
            return "display"
        }
    }

    private func reportShareSheet(_ item: ReportShareItem) -> some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.accent)

                Text(item.title)
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.ColorToken.textPrimary)

                Text("Professional PDF report is ready to save or share.")
                    .foregroundStyle(AppTheme.ColorToken.textSecondary)
                    .multilineTextAlignment(.center)

                ShareLink(item: item.url) {
                    Label("Save or Share PDF", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.ColorToken.accent)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.ColorToken.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        reportShareItem = nil
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct ReportShareItem: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

#Preview {
    MonitoringDashboardView()
        .environmentObject(AppSessionStore())
}
