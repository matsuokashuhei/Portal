//
//  PortalApp.swift
//  Portal
//
//  Created by 松岡周平 on 2025/12/29.
//

import SwiftUI

@main
struct PortalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar app (LSUIElement=YES) doesn't need visible windows.
        // Settings is handled by AppDelegate via custom SettingsWindow,
        // which provides ESC key dismissal via cancelOperation(_:).
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}
