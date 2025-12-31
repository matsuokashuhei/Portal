//
//  Notifications.swift
//  Portal
//
//  Created by Claude Code on 2025/12/31.
//

import AppKit

extension Notification.Name {
    /// Posted when the command palette panel is shown.
    /// The userInfo dictionary may contain a `targetApp` key with the NSRunningApplication to crawl, if a target app was specified.
    static let panelDidShow = Notification.Name("Portal.panelDidShow")
}

/// Keys for notification userInfo dictionaries.
enum NotificationUserInfoKey {
    /// Key for the target application (NSRunningApplication) to crawl menus from.
    static let targetApp = "targetApp"
}
