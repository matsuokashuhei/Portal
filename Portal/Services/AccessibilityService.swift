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
        // macOS 13+ (Ventura and later) uses the x-apple.systemsettings URL scheme
        guard let url = URL(string: "x-apple.systemsettings://com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
