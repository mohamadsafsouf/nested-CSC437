//
//  NetSeciOSApp.swift
//  NetSeciOS
//
//  Created by Mohamad Safsouf on 4/26/26.
//

import SwiftUI

@main
struct NetSeciOSApp: App {
    @StateObject private var session = AppSessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
        }
    }
}
