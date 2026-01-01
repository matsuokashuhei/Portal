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
}

/// Keys for notification userInfo dictionaries.
enum NotificationUserInfoKey {
    /// Key for the target application (NSRunningApplication) to crawl menus from.
    static let targetApp = "targetApp"
}
