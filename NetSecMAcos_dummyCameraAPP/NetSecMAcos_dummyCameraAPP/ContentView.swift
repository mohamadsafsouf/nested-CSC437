//
//  ContentView.swift
//  NetSecMAcos_dummyCameraAPP
//
//  Created by Mohamad Safsouf on 4/26/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var tester = CameraActivationTester()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statusGrid
                controls
                backendSection
                eventLog
            }
            .padding(28)
            .frame(width: 620, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("UnknownCameraClient", systemImage: "video.badge.ellipsis")
                .font(.largeTitle.weight(.semibold))
            Text("Opens the camera briefly to test CamGuard detection. It never records video, saves images, or uploads camera content.")
                .foregroundStyle(.secondary)
        }
    }

    private var statusGrid: some View {
        HStack(spacing: 12) {
            statusCard(title: "Permission", value: tester.permissionStatusTitle, systemImage: "hand.raised")
            statusCard(title: "Camera", value: tester.isCameraRunning ? "Open" : "Closed", systemImage: "camera")
            statusCard(title: "Threat", value: tester.threatLevel, systemImage: "exclamationmark.shield")
        }
    }

    private func statusCard(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Camera Test")
                .font(.headline)

            HStack {
                Button {
                    Task { await tester.requestCameraPermission() }
                } label: {
                    Label("Request Permission", systemImage: "hand.tap")
                }

                Button {
                    tester.openCameraOnce()
                } label: {
                    Label("Open 3 Seconds", systemImage: "play.circle")
                }
                .buttonStyle(.borderedProminent)

                Button(role: tester.isSequenceRunning ? .cancel : nil) {
                    tester.isSequenceRunning ? tester.cancelSequence() : tester.runRepeatedShortActivationTest()
                } label: {
                    Label(tester.isSequenceRunning ? "Stop Test" : "Run Repeated Test", systemImage: tester.isSequenceRunning ? "stop.circle" : "repeat.circle")
                }

                Button {
                    tester.runCameraNetworkActivityTest()
                } label: {
                    Label("Camera + Network", systemImage: "network")
                }
                .disabled(!tester.canRunNetworkTest)

                Button {
                    tester.runCriticalCameraMetadataTest()
                } label: {
                    Label("Critical Test", systemImage: "exclamationmark.octagon")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .controlSize(.large)
            .disabled(tester.isCameraRunning && !tester.isSequenceRunning)

            Text(tester.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var backendSection: some View {
        DisclosureGroup("Backend test requests") {
            VStack(alignment: .leading, spacing: 10) {
                Text("The camera + network test sends `{ event_type, app_name, dummy_upload, payload }` after camera close. Camera media is never included.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("Critical Test uses the local backend and `.env` service configuration, so no bearer token is needed for that test.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                TextField("Backend URL", text: $tester.backendURLString)
                    .textFieldStyle(.roundedBorder)

                Text(tester.networkTestStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Text("Authenticated metadata sync is optional for manual sends and stores only metadata fields such as duration, activation count, process identity, and whether a test network event followed camera use.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                TextField("Device UUID", text: $tester.deviceIDString)
                    .textFieldStyle(.roundedBorder)
                SecureField("Bearer token", text: $tester.bearerToken)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task { await tester.sendDummyMetadata() }
                } label: {
                    Label("Send Dummy Metadata", systemImage: "paperplane")
                }
                .disabled(!tester.canSendMetadata)

                Text(tester.metadataStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 10)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var eventLog: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Local Events")
                .font(.headline)
            ForEach(tester.eventLog, id: \.self) { item in
                Text(item)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    ContentView()
}
