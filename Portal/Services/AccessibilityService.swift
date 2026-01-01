//
//  AccessibilityService.swift
//  Portal
//
//  Created by Claude Code on 2025/12/30.
//

import ApplicationServices
import AppKit

/// Service for managing accessibility permissions required by Portal.
/// Portal needs accessibility access to read menu items from other applications.
struct AccessibilityService {

    /// Checks if the app has been granted accessibility permissions.
    /// Returns `true` if the app is trusted, `false` otherwise.
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Requests accessibility permission from the user.
    /// Shows the system dialog prompting user to grant permission if not already granted.
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        // Intentionally discard return value; the dialog side effect is the primary purpose
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings directly to the Accessibility privacy pane.
    /// Use this when the user needs guidance on where to enable permissions.
    static func openAccessibilitySettings() {
        let workspace = NSWorkspace.shared

        // Try x-apple.systempreferences first (confirmed working on macOS 15)
        if let preferencesURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
           workspace.open(preferencesURL) {
            return
        }

        // Fallback to x-apple.systemsettings (macOS 13+ documented scheme)
        if let settingsURL = URL(string: "x-apple.systemsettings:com.apple.preference.security?Privacy_Accessibility") {
            workspace.open(settingsURL)
        }
    }
}
