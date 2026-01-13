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

    private let center: NotificationCenter
    private let lock = NSLock()
    private var observerTokens: [NSObjectProtocol] = []

    init(center: NotificationCenter = .default) {
        self.center = center
    }

    func start(onEvent: @escaping (Event) -> Void) {
        // Make start idempotent
        stop()

        // App becomes active (e.g. returning from System Settings)
        let tokens: [NSObjectProtocol] = [
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                onEvent(.applicationDidBecomeActive)
            },
            // Settings changes
            center.addObserver(
                forName: .hotkeyConfigurationChanged,
                object: nil,
                queue: .main
            ) { _ in
                onEvent(.hotkeyConfigurationChanged)
            },
            center.addObserver(
                forName: .excludedAppsConfigurationChanged,
                object: nil,
                queue: .main
            ) { _ in
                onEvent(.excludedAppsConfigurationChanged)
            },
            // Open settings request
            center.addObserver(
                forName: .openSettings,
                object: nil,
                queue: .main
            ) { _ in
                onEvent(.openSettingsRequested)
            },
        ]

        lock.lock()
        observerTokens.append(contentsOf: tokens)
        lock.unlock()
    }

    func stop() {
        lock.lock()
        let tokens = observerTokens
        observerTokens.removeAll()
        lock.unlock()

        guard !tokens.isEmpty else { return }
        tokens.forEach { center.removeObserver($0) }
    }

    deinit {
        stop()
    }
}
