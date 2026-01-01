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
        // Menu bar app (LSUIElement=YES) doesn't show in Dock or app switcher.
        // The zero-sized EmptyView with hiddenTitleBar prevents any visible window.
        // Settings is handled by AppDelegate via custom SettingsWindow,
        // which provides ESC key dismissal via cancelOperation(_:).
        //
        // Alternative approaches considered:
        // - Using no Scene at all: requires removing @main and manual NSApplication setup
        // - SwiftUI Settings scene: doesn't support ESC dismissal natively
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}
