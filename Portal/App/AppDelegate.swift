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
    private var permissionCheckTimer: Timer?
    private var wasPermissionGranted = false
    private var isCheckingPermission = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        // Skip accessibility check in test mode to avoid permission dialogs
        if !TestConfiguration.shouldSkipAccessibilityCheck {
            checkAccessibilityPermission()
            startPermissionCheckTimer()
        }

        wasPermissionGranted = AccessibilityService.isGranted
        setupHotkeyManager()
        setupPermissionObserver()

        // Auto-show panel for UI testing (XCUITest cannot simulate global hotkeys)
        if TestConfiguration.shouldShowPanelOnLaunch {
            DispatchQueue.main.async { [weak self] in
                self?.panelController.show()
            }
        }
    }

    private func setupPermissionObserver() {
        // Update permission status when app becomes active (e.g., after returning from System Settings)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func applicationDidBecomeActive() {
        checkAndHandlePermissionChange()
        updatePermissionMenuItemIfNeeded()
    }

    private func startPermissionCheckTimer() {
        // Poll every 1 second to detect permission changes
        // Timer callbacks run on main run loop, ensuring thread safety with applicationDidBecomeActive
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // Explicitly dispatch to main queue to guarantee thread safety
            DispatchQueue.main.async {
                self?.checkAndHandlePermissionChange()
            }
        }
    }

    private func stopPermissionCheckTimer() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }

    private func checkAndHandlePermissionChange() {
        // Prevent concurrent execution from timer and applicationDidBecomeActive
        guard !isCheckingPermission else { return }
        isCheckingPermission = true
        defer { isCheckingPermission = false }

        let isNowGranted = AccessibilityService.isGranted

        if !wasPermissionGranted && isNowGranted {
            restartHotkeyManager()
            updatePermissionMenuItemIfNeeded()
            stopPermissionCheckTimer()
        }

        wasPermissionGranted = isNowGranted
    }

    private func restartHotkeyManager() {
        guard let hotkeyManager = hotkeyManager else { return }
        hotkeyManager.stop()
        hotkeyManager.start()
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
            } else {
                // Provide feedback that the hotkey was received but waiting for permission
                NSSound.beep()
            }
            updatePermissionMenuItemIfNeeded()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Initialize icon based on current permission state to avoid flicker
        updateStatusBarIcon(isGranted: AccessibilityService.isGranted)

        // Add accessibility identifier to status item button
        if let button = statusItem?.button {
            button.setAccessibilityIdentifier("PortalStatusBarButton")
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.setAccessibilityIdentifier("PortalStatusBarMenu")

        let permissionItem = NSMenuItem(
            title: "Grant Accessibility Permission...",
            action: #selector(openAccessibilityPermissions),
            keyEquivalent: ""
        )
        permissionItem.target = self
        permissionItem.isHidden = AccessibilityService.isGranted
        permissionItem.setAccessibilityIdentifier("GrantPermissionMenuItem")
        menu.addItem(permissionItem)
        self.permissionMenuItem = permissionItem

        let separator = NSMenuItem.separator()
        separator.isHidden = AccessibilityService.isGranted
        menu.addItem(separator)
        self.permissionSeparator = separator

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.setAccessibilityIdentifier("SettingsMenuItem")
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Portal", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        quitItem.setAccessibilityIdentifier("QuitMenuItem")
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

        updateStatusBarIcon(isGranted: isGranted)
    }

    private func updateStatusBarIcon(isGranted: Bool) {
        guard let button = statusItem?.button else { return }
        let symbolName = isGranted ? "command" : "exclamationmark.triangle"
        let description = isGranted ? "Portal Menu" : "Portal - Permission Required"
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
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

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopPermissionCheckTimer()
    }
}
