//
//  Notifications.swift
//  Portal
//
//  Created by Claude Code on 2025/12/31.
//

import Foundation

extension Notification.Name {
    /// Posted when the hotkey configuration changes in Settings.
    static let hotkeyConfigurationChanged = Notification.Name("com.matsuokashuhei.Portal.hotkeyConfigurationChanged")

    /// Posted when the excluded apps configuration changes in Settings.
    static let excludedAppsConfigurationChanged = Notification.Name("com.matsuokashuhei.Portal.excludedAppsConfigurationChanged")

    /// Posted when user requests to open Settings (e.g., from status bar menu).
    static let openSettings = Notification.Name("com.matsuokashuhei.Portal.openSettings")

    /// Posted when hint mode is activated.
    static let hintModeDidActivate = Notification.Name("com.matsuokashuhei.Portal.hintModeDidActivate")

    /// Posted when hint mode is deactivated.
    static let hintModeDidDeactivate = Notification.Name("com.matsuokashuhei.Portal.hintModeDidDeactivate")
}
