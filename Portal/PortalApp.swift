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
        Settings {
            Text("Settings")
                .frame(width: 300, height: 200)
        }
    }
}
