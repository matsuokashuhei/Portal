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
    private var hintModeHotkeyManager: HotkeyManager?
    private var settingsWindow: NSWindow?
    private var settingsWindowObserver: NSObjectProtocol?

    private var permissionMenuItem: NSMenuItem?
    private var permissionSeparator: NSMenuItem?

    private var lastPermissionRequestTime: Date?
    private let permissionRequestCooldown: TimeInterval = 5.0
    private var permissionCheckTimer: Timer?
    private var wasPermissionGranted = false
    private var isCheckingPermission = false
    private var isRecreatingHotkeyManager = false

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
        setupHintModeHotkeyManager()
        setupScrollMode()
        setupPermissionObserver()
        setupHotkeyConfigurationObserver()
        setupOpenSettingsObserver()
    }

    private func setupScrollMode() {
        // Start scroll mode if accessibility permission is granted
        // If not granted, it will be started when permission is granted
        if AccessibilityService.isGranted {
            ScrollModeController.shared.start()
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
                ScrollModeController.shared.start()
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
        hintModeHotkeyManager?.stop()
        hintModeHotkeyManager?.start()
    }

    private func checkAccessibilityPermission() {
        if !AccessibilityService.isGranted {
            AccessibilityService.requestPermission()
            lastPermissionRequestTime = Date()
        }
        updatePermissionMenuItemIfNeeded()
    }

    private func setupHintModeHotkeyManager() {
        // Load hint mode hotkey configuration from UserDefaults
        let config = HotkeyConfiguration.load()
        hintModeHotkeyManager = HotkeyManager(configuration: config) { [weak self] in
            self?.handleHintModeHotkeyPressed()
        }
        hintModeHotkeyManager?.start()
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
        // Ensure we're on the main thread since hotkeyManager manages
        // UI-related event monitors and run loop sources
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Prevent concurrent recreation if multiple notifications arrive rapidly
            guard !self.isRecreatingHotkeyManager else { return }
            self.isRecreatingHotkeyManager = true
            defer { self.isRecreatingHotkeyManager = false }

            // Recreate HintModeHotkeyManager with new configuration
            self.hintModeHotkeyManager?.stop()
            self.hintModeHotkeyManager = nil
            self.setupHintModeHotkeyManager()
        }
    }

    private func setupOpenSettingsObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettings),
            name: .openSettings,
            object: nil
        )
    }

    private func handleHintModeHotkeyPressed() {
        // Toggle hint mode if already active
        guard !HintModeController.shared.isActive else {
            HintModeController.shared.deactivate()
            return
        }

        if AccessibilityService.isGranted {
            // Capture the frontmost app BEFORE activating hint mode
            let frontmostApp = NSWorkspace.shared.frontmostApplication
            let targetApp: NSRunningApplication?
            if let app = frontmostApp,
               app.bundleIdentifier != Bundle.main.bundleIdentifier {
                targetApp = app
            } else {
                targetApp = nil
            }

            // Ignore when no active app
            guard let targetApp else { return }

            HintModeController.shared.activate(for: targetApp)
        } else {
            // Beep if permission not granted
            NSSound.beep()
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

        // Create custom SettingsWindow with NSHostingController
        // This approach allows ESC key handling via cancelOperation(_:)
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = SettingsWindow(contentViewController: hostingController)
        window.title = "Portal Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 450, height: 250))
        window.center()

        window.isReleasedWhenClosed = false

        // Remove previous observer if exists (handles rapid open/close cycles)
        if let observer = settingsWindowObserver {
            NotificationCenter.default.removeObserver(observer)
            settingsWindowObserver = nil
        }

        // Observe window close to cleanup references
        // Block-based observers MUST be explicitly removed via removeObserver()
        // Setting settingsWindowObserver to nil alone does NOT unregister it
        settingsWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // Remove self (the observer) when window closes
            if let observer = self.settingsWindowObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            self.settingsWindowObserver = nil
            self.settingsWindow = nil
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
        if let observer = settingsWindowObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        stopPermissionCheckTimer()
        // Note: ScrollModeController.shared.stop() is not called here because:
        // 1. deinit is nonisolated and cannot call MainActor-isolated methods synchronously
        // 2. App termination will clean up all resources anyway
    }
}

// MARK: - SettingsWindow

/// Custom NSWindow for the settings UI that supports ESC key dismissal.
///
/// SwiftUI's `Settings` scene does not natively support ESC key dismissal.
/// By using a custom NSWindow with `cancelOperation(_:)` override, we can
/// reliably handle ESC key regardless of which control has focus.
final class SettingsWindow: NSWindow {
    /// Handles the Escape key press to close the window.
    ///
    /// `cancelOperation(_:)` is the standard NSResponder method for handling ESC key.
    /// Unlike `keyDown(with:)`, it works reliably even when SwiftUI controls
    /// (Picker, TextField, etc.) have focus.
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
