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

        // macOS 13+ (Ventura) renamed System Preferences to System Settings
        // and uses x-apple.systemsettings scheme. Since Portal targets macOS 15+,
        // this is the primary scheme.
        if let settingsURL = URL(string: "x-apple.systemsettings:com.apple.preference.security?Privacy_Accessibility"),
           workspace.open(settingsURL) {
            return
        }

        // Fallback to x-apple.systempreferences for older macOS versions (macOS 12 and earlier)
        if let preferencesURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            workspace.open(preferencesURL)
        }
    }
}
