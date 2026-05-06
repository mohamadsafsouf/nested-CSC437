import SwiftUI

struct MonitoringDashboardView: View {
    @EnvironmentObject private var session: AppSessionStore

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    switch session.selectedTab {
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
                .frame(maxWidth: AppTheme.Layout.contentMaxWidth, alignment: .leading)
                .padding(30)
            }
            .background(AppTheme.ColorToken.background)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
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
                    Text(session.currentUser?.email ?? "Not signed in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 10)

            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        session.selectedTab = tab
                    }
                } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(session.selectedTab == tab ? AppTheme.ColorToken.accent.opacity(0.16) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button(role: .destructive) {
                Task {
                    await session.signOut()
                }
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
        .padding(18)
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 300)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text(session.selectedTab.title)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ColorToken.textPrimary)

                Text(headerSubtitle)
                    .foregroundStyle(AppTheme.ColorToken.textSecondary)
            }

            Spacer()

            backendStatusBadge
        }
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

            HStack(spacing: 16) {
                ForEach(session.monitoringSnapshots) { snapshot in
                    statusCard(snapshot)
                }
            }

            placeholderPanel(
                title: "Privacy Boundary",
                message: "CamGuard stores metadata only. No camera media is captured, stored, or uploaded."
            )
        }
    }

    private var healthKPIPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Health KPIs")
                .font(.title2.bold())

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
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
                    .padding(14)
                    .background(AppTheme.ColorToken.panelElevated.opacity(0.62))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.compactCornerRadius, style: .continuous))
                }
            }
        }
        .foregroundStyle(AppTheme.ColorToken.textPrimary)
        .camGuardPanel()
    }

    private var headerSubtitle: String {
        switch session.selectedTab {
        case .overview:
            return "Your Mac is enrolled for camera security monitoring and metadata-only reporting."
        case .activity:
            return "Review camera, permission, process, and network signals as they are collected."
        case .devices:
            return "Manage trusted devices associated with your CamGuard account."
        case .settings:
            return "Control your session, cloud sync, and privacy preferences."
        }
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
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Session")
                .font(.title2.bold())

            Text("Signed in as \(session.currentUser?.email ?? "unknown"). Your secure session remains on this Mac until you sign out.")
                .foregroundStyle(AppTheme.ColorToken.textSecondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Cloud Sync")
                    .font(.headline)
                Text(session.backendConnectionState.detail)
                    .foregroundStyle(AppTheme.ColorToken.textSecondary)
            }

            Button("Refresh Cloud Status") {
                Task {
                    await session.checkBackendConnection()
                    await session.syncCurrentDevice()
                }
            }
            .buttonStyle(.bordered)

            Button("Sign out") {
                Task {
                    await session.signOut()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .foregroundStyle(AppTheme.ColorToken.textPrimary)
        .camGuardPanel()
    }

    private var activityPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent Activity")
                        .font(.title2.bold())
                    Text("Live camera and permission changes detected on this Mac.")
                        .foregroundStyle(AppTheme.ColorToken.textSecondary)
                }
                Spacer()
                Button {
                    Task {
                        session.startMonitoring()
                        await session.refreshSavedActivityNow()
                    }
                } label: {
                    Label("Watch Now", systemImage: "dot.radiowaves.left.and.right")
                }
                .buttonStyle(.bordered)
            }

            if session.activityEvents.isEmpty {
                emptyActivityState
            } else {
                ForEach(session.activityEvents) { event in
                    activityRow(event)
                }
            }
        }
        .foregroundStyle(AppTheme.ColorToken.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .camGuardPanel()
    }

    private var emptyActivityState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Watching for camera activity", systemImage: "video.badge.ellipsis")
                .font(.headline)
            Text("Open or close FaceTime, Photo Booth, or another camera app to create a realtime event. CamGuard stores metadata only, never camera images or video.")
                .foregroundStyle(AppTheme.ColorToken.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppTheme.ColorToken.panelElevated.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.compactCornerRadius, style: .continuous))
    }

    private func activityRow(_ event: SecurityActivityEvent) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: event.kind.icon)
                .font(.title3)
                .foregroundStyle(event.status.color)
                .frame(width: 38, height: 38)
                .background(event.status.color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(event.title)
                        .font(.headline)
                    if let appName = event.observedApplicationName, !appName.isEmpty {
                        Text(appName)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.ColorToken.panelElevated)
                            .clipShape(Capsule())
                    }
                }
                Text(event.detail)
                    .font(.callout)
                    .foregroundStyle(AppTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if event.requiresProtectionControls, event.threatLevel != nil {
                    protectionControls(for: event)
                } else if event.requiresProtectionControls {
                    Label("Awaiting backend verdict", systemImage: "hourglass")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.ColorToken.textSecondary)
                }
            }

            Spacer()

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
        .padding(14)
        .background(AppTheme.ColorToken.panelElevated.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.compactCornerRadius, style: .continuous))
    }

    private func protectionControls(for event: SecurityActivityEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let result = event.protectionResult {
                Label(result.status, systemImage: result.success ? "checkmark.shield" : "exclamationmark.triangle")
                    .font(.caption.bold())
                    .foregroundStyle(result.success ? AppTheme.ColorToken.accent : AppTheme.ColorToken.warning)
            } else if let decision = event.protectionDecision {
                Label(decision.requiresConfirmation ? "User confirmation required" : decision.action.title, systemImage: "shield.lefthalf.filled")
                    .font(.caption.bold())
                    .foregroundStyle(event.status.color)
            }

            HStack(spacing: 10) {
                if let decision = event.protectionDecision {
                    Button {
                        Task {
                            await session.stopApp(for: event.id)
                        }
                    } label: {
                        Label(decision.primaryButtonTitle, systemImage: decision.canStopApp ? "xmark.octagon" : "gearshape")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(decision.canStopApp ? (event.status == .critical ? AppTheme.ColorToken.critical : AppTheme.ColorToken.warning) : AppTheme.ColorToken.accent)
                    .disabled(event.protectionResult?.success == true || decision.action == .warnOnly || decision.action == .none)
                }

                Button {
                    Task {
                        await session.downloadReport(for: event.id)
                    }
                } label: {
                    Label("Download Report", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.bordered)
                .tint(.cyan)

                Button {
                    Task {
                        await session.trustSource(for: event.id)
                    }
                } label: {
                    Label(event.isWebsiteAttributed ? "Trust Website" : "Trust App", systemImage: "checkmark.shield")
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.ColorToken.accent)
            }
            .controlSize(.small)
        }
        .padding(.top, 4)
    }

    private var devicesPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Trusted Devices")
                        .font(.title2.bold())
                    Text(deviceSummary)
                        .foregroundStyle(AppTheme.ColorToken.textSecondary)
                }
                Spacer()
                Button {
                    Task {
                        await session.syncCurrentDevice()
                    }
                } label: {
                    Label(session.isSyncingDevices ? "Syncing" : "Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(session.isSyncingDevices)
            }

            if session.registeredDevices.isEmpty {
                emptyDeviceState
            } else {
                ForEach(session.registeredDevices) { device in
                    deviceRow(device)
                }
            }
        }
        .foregroundStyle(AppTheme.ColorToken.textPrimary)
        .camGuardPanel()
    }

    private var deviceSummary: String {
        if let currentDevice = session.currentDevice {
            return "\(currentDevice.displayName) is enrolled and syncing securely."
        }
        if session.isSyncingDevices {
            return "Enrolling this Mac with your account."
        }
        return "This Mac will be enrolled automatically after cloud sync completes."
    }

    private var emptyDeviceState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No devices synced yet")
                .font(.headline)
            Text("Keep the app open for a moment, or refresh to enroll this Mac.")
                .foregroundStyle(AppTheme.ColorToken.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppTheme.ColorToken.panelElevated.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.compactCornerRadius, style: .continuous))
    }

    private func deviceRow(_ device: RegisteredDevice) -> some View {
        HStack(spacing: 14) {
            Image(systemName: device.deviceTypeKey == "ios" ? "iphone" : "desktopcomputer")
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
                Text("This Mac")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.ColorToken.accent.opacity(0.18))
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .background(AppTheme.ColorToken.panelElevated.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.compactCornerRadius, style: .continuous))
    }

    private func placeholderPanel(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.bold())

            Text(message)
                .foregroundStyle(AppTheme.ColorToken.textSecondary)
        }
        .foregroundStyle(AppTheme.ColorToken.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .camGuardPanel()
    }
}

#Preview {
    MonitoringDashboardView()
        .environmentObject(AppSessionStore())
}
