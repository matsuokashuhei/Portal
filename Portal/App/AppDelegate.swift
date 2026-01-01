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
    private var settingsWindow: NSWindow?

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
            // Only start timer if permission is not already granted
            if !AccessibilityService.isGranted {
                startPermissionCheckTimer()
            }
        }

        wasPermissionGranted = AccessibilityService.isGranted
        setupHotkeyManager()
        setupPermissionObserver()
        setupHotkeyConfigurationObserver()

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
        dispatchPrecondition(condition: .onQueue(.main))
        checkAndHandlePermissionChange()
        updatePermissionMenuItemIfNeeded()
    }

    private func startPermissionCheckTimer() {
        // Poll every 1 second to detect permission changes
        // Timer.scheduledTimer runs on main run loop, callback is guaranteed to be on main thread
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkAndHandlePermissionChange()
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

        // Always stop timer when permission is granted to ensure it doesn't run indefinitely
        if isNowGranted {
            stopPermissionCheckTimer()
            if !wasPermissionGranted {
                restartHotkeyManager()
                updatePermissionMenuItemIfNeeded()
            }
        }

        // Only update state when it actually changes
        if wasPermissionGranted != isNowGranted {
            wasPermissionGranted = isNowGranted
        }
    }

    private func restartHotkeyManager() {
        // stop() must be called before start() because start() is not idempotent
        // (it adds monitors without checking if they already exist)
        hotkeyManager?.stop()
        hotkeyManager?.start()
    }

    private func checkAccessibilityPermission() {
        if !AccessibilityService.isGranted {
            AccessibilityService.requestPermission()
            lastPermissionRequestTime = Date()
        }
        updatePermissionMenuItemIfNeeded()
    }

    private func setupHotkeyManager() {
        let config = HotkeyConfiguration.load()
        hotkeyManager = HotkeyManager(configuration: config) { [weak self] in
            self?.handleHotkeyPressed()
        }
        hotkeyManager?.start()
    }

    private func setupHotkeyConfigurationObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyConfigurationDidChange),
            name: .hotkeyConfigurationChanged,
            object: nil
        )
    }

    @objc private func hotkeyConfigurationDidChange() {
        // Recreate HotkeyManager with new configuration
        hotkeyManager?.stop()
        hotkeyManager = nil
        setupHotkeyManager()
    }

    private func handleHotkeyPressed() {
        if AccessibilityService.isGranted {
            // Capture the frontmost app BEFORE showing the panel (Portal will become frontmost)
            // Filter out Portal itself to avoid semantically incorrect targetApp when panel is visible
            let frontmostApp = NSWorkspace.shared.frontmostApplication
            let targetApp: NSRunningApplication?
            if let app = frontmostApp,
               app.bundleIdentifier != Bundle.main.bundleIdentifier {
                targetApp = app
            } else {
                targetApp = nil
            }
            panelController.toggle(targetApp: targetApp)
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
        // If window already exists, just bring it to front
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create settings window with NSHostingController
        // (SwiftUI Settings scene doesn't work well with menu bar apps)
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = SettingsWindow(contentViewController: hostingController)
        window.title = "Portal Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 450, height: 250))
        window.center()

        // Clean up reference when window closes
        window.isReleasedWhenClosed = false
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.settingsWindow = nil
        }

        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopPermissionCheckTimer()
    }
}

// MARK: - SettingsWindow

/// Custom NSWindow that closes on Escape key press.
final class SettingsWindow: NSWindow {
    override func keyDown(with event: NSEvent) {
        // Escape key code is 53
        if event.keyCode == 53 {
            close()
        } else {
            super.keyDown(with: event)
        }
    }
}
