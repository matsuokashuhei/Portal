//
//  Notifications.swift
//  Portal
//
//  Created by Claude Code on 2025/12/31.
//

import Foundation

extension Notification.Name {
    /// Posted when the command palette panel is shown.
    /// The userInfo dictionary may contain a `targetApp` key with the NSRunningApplication to crawl, if a target app was specified.
    static let panelDidShow = Notification.Name("com.matsuokashuhei.Portal.panelDidShow")

    /// Posted when user presses arrow up in the command palette.
    static let navigateUp = Notification.Name("com.matsuokashuhei.Portal.navigateUp")

    /// Posted when user presses arrow down in the command palette.
    static let navigateDown = Notification.Name("com.matsuokashuhei.Portal.navigateDown")

    /// Posted when user presses Enter to execute selected command.
    static let executeSelectedCommand = Notification.Name("com.matsuokashuhei.Portal.executeSelectedCommand")

    /// Posted when the panel should hide (e.g., after command execution).
    static let hidePanel = Notification.Name("com.matsuokashuhei.Portal.hidePanel")

    /// Posted when the hotkey configuration changes in Settings.
    static let hotkeyConfigurationChanged = Notification.Name("com.matsuokashuhei.Portal.hotkeyConfigurationChanged")

    /// Posted when user requests to open Settings (e.g., Cmd+, from panel).
    static let openSettings = Notification.Name("com.matsuokashuhei.Portal.openSettings")

    /// Posted when user presses Cmd+1 to toggle menu items filter.
    static let toggleMenuFilter = Notification.Name("com.matsuokashuhei.Portal.toggleMenuFilter")

    /// Posted when user presses Cmd+2 to toggle sidebar items filter.
    static let toggleSidebarFilter = Notification.Name("com.matsuokashuhei.Portal.toggleSidebarFilter")
}

/// Keys for notification userInfo dictionaries.
enum NotificationUserInfoKey {
    /// Key for the target application (NSRunningApplication) to crawl menus from.
    static let targetApp = "targetApp"

    /// Key for restoreFocus flag (Bool) in hidePanel notification.
    static let restoreFocus = "restoreFocus"
}
