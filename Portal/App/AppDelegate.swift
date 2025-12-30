//
//  AppDelegate.swift
//  Portal
//
//  Created by Claude Code on 2025/12/30.
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var hotkeyManager: HotkeyManager?
    private let panelController = PanelController()

    private var permissionMenuItem: NSMenuItem?
    private var permissionSeparator: NSMenuItem?

    private var lastPermissionRequestTime: Date?
    private let permissionRequestCooldown: TimeInterval = 5.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        checkAccessibilityPermission()
        setupHotkeyManager()
        updatePermissionMenuItemIfNeeded()
    }

    private func checkAccessibilityPermission() {
        if !AccessibilityService.isGranted {
            AccessibilityService.requestPermission()
            lastPermissionRequestTime = Date()
        }
        updatePermissionMenuItemIfNeeded()
    }

    private func setupHotkeyManager() {
        hotkeyManager = HotkeyManager { [weak self] in
            self?.handleHotkeyPressed()
        }
        hotkeyManager?.start()
    }

    private func handleHotkeyPressed() {
        if AccessibilityService.isGranted {
            panelController.toggle()
        } else {
            let shouldPrompt: Bool
            if let lastRequest = lastPermissionRequestTime {
                shouldPrompt = Date().timeIntervalSince(lastRequest) >= permissionRequestCooldown
            } else {
                shouldPrompt = true
            }

            if shouldPrompt {
                AccessibilityService.requestPermission()
                lastPermissionRequestTime = Date()
            }
            updatePermissionMenuItemIfNeeded()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Initialize icon based on current permission state to avoid flicker
        if let button = statusItem?.button {
            let isGranted = AccessibilityService.isGranted
            let symbolName = isGranted ? "command" : "exclamationmark.triangle"
            let description = isGranted ? "Portal Menu" : "Portal - Permission Required"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        }

        let menu = NSMenu()
        menu.delegate = self

        let permissionItem = NSMenuItem(
            title: "Grant Accessibility Permission...",
            action: #selector(openAccessibilityPermissions),
            keyEquivalent: ""
        )
        permissionItem.target = self
        permissionItem.isHidden = AccessibilityService.isGranted
        menu.addItem(permissionItem)
        self.permissionMenuItem = permissionItem

        let separator = NSMenuItem.separator()
        separator.isHidden = AccessibilityService.isGranted
        menu.addItem(separator)
        self.permissionSeparator = separator

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit Portal", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        updatePermissionMenuItemIfNeeded()
    }

    private func updatePermissionMenuItemIfNeeded() {
        let isGranted = AccessibilityService.isGranted
        permissionMenuItem?.isHidden = isGranted
        permissionSeparator?.isHidden = isGranted

        // Reset cooldown when permission is granted
        if isGranted {
            lastPermissionRequestTime = nil
        }

        if let button = statusItem?.button {
            let symbolName = isGranted ? "command" : "exclamationmark.triangle"
            let description = isGranted ? "Portal Menu" : "Portal - Permission Required"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        }
    }

    @objc private func openAccessibilityPermissions() {
        AccessibilityService.openAccessibilitySettings()
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector("showSettingsWindow:"), to: nil, from: nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
