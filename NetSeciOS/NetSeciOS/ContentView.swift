//
//  ContentView.swift
//  NetSeciOS
//
//  Created by Mohamad Safsouf on 4/26/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: AppSessionStore

    var body: some View {
        ZStack(alignment: .top) {
            AnimatedBackgroundView()

            if session.isSignedIn {
                MonitoringDashboardView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                SignInView()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            }

            if let message = session.errorMessage {
                ErrorBannerView(message: message) {
                    session.dismissError()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: session.isSignedIn)
        .animation(.easeInOut(duration: 0.18), value: session.errorMessage)
        .task {
            await session.checkBackendConnection()
            await session.validateRestoredSession()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSessionStore())
}
