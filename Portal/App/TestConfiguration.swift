//
//  TestConfiguration.swift
//  Portal
//
//  Created by Claude Code on 2025/12/31.
//

import Foundation

/// Test configuration for Portal app.
/// Contains launch arguments and environment variables used during UI testing.
enum TestConfiguration {

    /// Launch argument keys
    enum LaunchArguments {
        /// When present, the panel will be shown automatically on app launch.
        /// This is necessary because XCUITest cannot simulate global hotkeys.
        static let showPanelOnLaunch = "--show-panel-on-launch"

        /// When present, skip accessibility permission check.
        /// Useful for UI testing where permission dialogs would interrupt tests.
        static let skipAccessibilityCheck = "--skip-accessibility-check"

        /// When present, disable panel auto-hide on focus loss.
        /// Useful for UI testing where the panel would otherwise hide when XCUITest interacts with it.
        static let disablePanelAutoHide = "--disable-panel-auto-hide"
    }

    /// Checks if a launch argument is present in the current process.
    /// - Parameter argument: The launch argument to check.
    /// - Returns: `true` if the argument is present, `false` otherwise.
    static func hasLaunchArgument(_ argument: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    /// Whether the app should show the panel on launch (for UI testing).
    static var shouldShowPanelOnLaunch: Bool {
        hasLaunchArgument(LaunchArguments.showPanelOnLaunch)
    }

    /// Whether to skip accessibility permission check (for UI testing).
    static var shouldSkipAccessibilityCheck: Bool {
        hasLaunchArgument(LaunchArguments.skipAccessibilityCheck)
    }

    /// Whether to disable panel auto-hide on focus loss (for UI testing).
    static var shouldDisablePanelAutoHide: Bool {
        hasLaunchArgument(LaunchArguments.disablePanelAutoHide)
    }

    /// Whether the app is running in UI test mode.
    /// Returns `true` if any test-related launch arguments are present.
    static var isTestMode: Bool {
        shouldShowPanelOnLaunch
            || shouldSkipAccessibilityCheck
            || shouldDisablePanelAutoHide
    }
}
