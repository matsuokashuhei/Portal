//
//  AppDelegate.swift
//  Portal
//
//  Created by Claude Code on 2025/12/30.
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotkeyManager: HotkeyManager?
    private let panelController = PanelController()

    private var permissionMenuItem: NSMenuItem?
    private var permissionSeparator: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        checkAccessibilityPermission()
        setupHotkeyManager()
    }

    private func checkAccessibilityPermission() {
        if !AccessibilityService.isGranted {
            AccessibilityService.requestPermission()
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
            AccessibilityService.requestPermission()
            updatePermissionMenuItemIfNeeded()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "command", accessibilityDescription: "Portal Menu")
        }

        let menu = NSMenu()

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

    private func updatePermissionMenuItemIfNeeded() {
        let isGranted = AccessibilityService.isGranted
        permissionMenuItem?.isHidden = isGranted
        permissionSeparator?.isHidden = isGranted

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
