//
//  AppNotificationBindings.swift
//  Portal
//
//  Created by GPT-5.2 on 2026/01/13.
//

import AppKit
import Foundation

/// Centralizes app-lifetime NotificationCenter observers to keep `AppDelegate` slim
/// and to ensure observer tokens are managed in one place.
final class AppNotificationBindings {
    enum Event: Equatable {
        case applicationDidBecomeActive
        case hotkeyConfigurationChanged
        case excludedAppsConfigurationChanged
        case openSettingsRequested
    }

    private var observerTokens: [NSObjectProtocol] = []

    func start(onEvent: @escaping (Event) -> Void) {
        // Make start idempotent
        stop()

        let center = NotificationCenter.default

        // App becomes active (e.g. returning from System Settings)
        observerTokens.append(
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                onEvent(.applicationDidBecomeActive)
            }
        )

        // Settings changes
        observerTokens.append(
            center.addObserver(
                forName: .hotkeyConfigurationChanged,
                object: nil,
                queue: .main
            ) { _ in
                onEvent(.hotkeyConfigurationChanged)
            }
        )

        observerTokens.append(
            center.addObserver(
                forName: .excludedAppsConfigurationChanged,
                object: nil,
                queue: .main
            ) { _ in
                onEvent(.excludedAppsConfigurationChanged)
            }
        )

        // Open settings request
        observerTokens.append(
            center.addObserver(
                forName: .openSettings,
                object: nil,
                queue: .main
            ) { _ in
                onEvent(.openSettingsRequested)
            }
        )
    }

    func stop() {
        guard !observerTokens.isEmpty else { return }
        let center = NotificationCenter.default
        observerTokens.forEach { center.removeObserver($0) }
        observerTokens.removeAll()
    }

    deinit {
        stop()
    }
}
