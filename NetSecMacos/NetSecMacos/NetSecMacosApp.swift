//
//  NetSecMacosApp.swift
//  NetSecMacos
//
//  Created by Mohamad Safsouf on 4/26/26.
//

import SwiftUI

@main
struct NetSecMacosApp: App {
    @StateObject private var session = AppSessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .onOpenURL { url in
                    session.handleIncomingSimulatorURL(url)
                }
        }
        .windowStyle(.hiddenTitleBar)
    }
}
