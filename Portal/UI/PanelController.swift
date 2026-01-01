//
//  PanelController.swift
//  Portal
//
//  Created by Claude Code on 2025/12/30.
//

import AppKit
import SwiftUI

final class PanelController: NSObject, NSWindowDelegate {
    private static let escapeKeyCode: UInt16 = 53
    private static let upArrowKeyCode: UInt16 = 126
    private static let downArrowKeyCode: UInt16 = 125
    /// Return key on the main keyboard area.
    private static let returnKeyCode: UInt16 = 36
    /// Enter key on the numeric keypad (different from Return).
    private static let enterKeyCode: UInt16 = 76
    /// Comma key for Cmd+, settings shortcut.
    private static let commaKeyCode: UInt16 = 43

    // MARK: - Panel Size Calculation

    /// Height of the search field area including wrapper padding (16 + 48 + 16).
    private static let searchFieldHeight: CGFloat = 80
    /// Height of the divider between search field and results.
    private static let dividerHeight: CGFloat = 1
    /// Expected height of a single MenuItemRow, including its internal vertical padding.
    /// This value must stay in sync with the actual rendered height of `MenuItemRow`; if that
    /// view's layout (padding, font size, etc.) changes, update this constant to avoid visual misalignment.
    private static let itemHeight: CGFloat = 44
    /// Spacing between items in the results list.
    private static let itemSpacing: CGFloat = 4
    /// Number of visible items in the results list.
    private static let visibleItemCount: Int = 8

    /// Calculated panel size based on item dimensions.
    /// Height = searchFieldHeight + dividerHeight + (visibleItemCount × itemHeight) + ((visibleItemCount - 1) × itemSpacing)
    ///
    /// - Important: This value is computed once when the class loads. Changes to the layout constants
    ///   above require rebuilding the app to take effect.
    static let panelSize: NSSize = {
        let listHeight = CGFloat(visibleItemCount) * itemHeight + CGFloat(visibleItemCount - 1) * itemSpacing
        let totalHeight = searchFieldHeight + dividerHeight + listHeight
        return NSSize(width: 600, height: totalHeight)
    }()

    private var panel: NSPanel?
    private var keyboardMonitor: Any?
    private var hasBeenPositioned = false
    private var hidePanelObserver: NSObjectProtocol?
    private var targetApp: NSRunningApplication?

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func toggle(targetApp: NSRunningApplication? = nil) {
        if isVisible {
            hide()
        } else {
            show(targetApp: targetApp)
        }
    }

    func show(targetApp: NSRunningApplication? = nil) {
        self.targetApp = targetApp

        if panel == nil {
            createPanel()
        }

        guard let panel = panel else { return }

        if !hasBeenPositioned {
            centerPanelOnScreen(panel)
            hasBeenPositioned = true
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        stopKeyboardMonitor()
        startKeyboardMonitor()
        setupHidePanelObserver()

        // Post notification with target app info.
        // NOTE: targetApp is captured by the caller (AppDelegate) BEFORE showing the panel,
        // so observers can act on the original frontmost app. By the time this notification
        // is posted, Portal is already the frontmost application. When targetApp is nil,
        // observers should NOT attempt to infer the target from the current frontmost app.
        let userInfo: [String: Any] = targetApp.map { [NotificationUserInfoKey.targetApp: $0] } ?? [:]
        NotificationCenter.default.post(name: .panelDidShow, object: nil, userInfo: userInfo)
    }

    /// Hides the panel.
    ///
    /// - Parameter restoreFocus:
    ///   If `true`, restores focus to `targetApp` (the app that was frontmost before the panel was shown)
    ///   before hiding the panel. Use this when closing the panel via Escape key or after command execution.
    ///   If `false` (default), no focus restoration is performed. Use this when the panel is hidden
    ///   due to focus loss (e.g., user clicked another app), where explicit focus switching is unnecessary.
    ///
    /// - Note: Focus restoration must occur BEFORE `panel?.orderOut(nil)` because once the panel is
    ///   hidden, Portal may no longer have the ability to activate other applications reliably.
    func hide(restoreFocus: Bool = false) {
        if restoreFocus {
            restoreFocusToTargetApp()
        }
        stopKeyboardMonitor()
        removeHidePanelObserver()
        panel?.orderOut(nil)
        panel = nil
        hasBeenPositioned = false
        targetApp = nil
    }

    /// Restores focus to the original application that was frontmost before the panel was shown.
    ///
    /// If `targetApp` is `nil`, this method does nothing.
    private func restoreFocusToTargetApp() {
        guard let target = targetApp else { return }
        target.activate(options: [.activateIgnoringOtherApps])
    }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.title = "Portal Command Palette"
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.delegate = self
        // Add accessibility identifier for XCUITest
        panel.setAccessibilityIdentifier("CommandPalettePanel")

        let hostingView = NSHostingView(rootView: CommandPaletteView())
        panel.contentView = hostingView

        self.panel = panel
    }

    private func centerPanelOnScreen(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame

        let x = screenFrame.midX - panelFrame.width / 2
        let y = screenFrame.maxY - screenFrame.height / 4 - panelFrame.height / 2

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func startKeyboardMonitor() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Handle Cmd+, for opening Settings
            // This must be handled explicitly because menu keyboard shortcuts don't work
            // reliably when a floating panel has focus.
            if modifiers == .command && event.keyCode == Self.commaKeyCode {
                NotificationCenter.default.post(name: .openSettings, object: nil)
                return nil
            }

            // Only handle keys without user-intentional modifiers (Cmd, Opt, Ctrl, Shift).
            // Other modifiers like .numericPad, .function, and .capsLock are system-managed
            // and do not indicate user intent to modify the key.
            let userIntentionalModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
            guard modifiers.intersection(userIntentionalModifiers).isEmpty else { return event }

            switch event.keyCode {
            case Self.escapeKeyCode:
                self?.hide(restoreFocus: true)
                return nil

            case Self.upArrowKeyCode:
                NotificationCenter.default.post(name: .navigateUp, object: nil)
                return nil

            case Self.downArrowKeyCode:
                NotificationCenter.default.post(name: .navigateDown, object: nil)
                return nil

            case Self.returnKeyCode, Self.enterKeyCode:
                NotificationCenter.default.post(name: .executeSelectedCommand, object: nil)
                return nil

            default:
                return event
            }
        }
    }

    private func stopKeyboardMonitor() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
    }

    private func setupHidePanelObserver() {
        removeHidePanelObserver()
        hidePanelObserver = NotificationCenter.default.addObserver(
            forName: .hidePanel,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let restoreFocus = notification.userInfo?[NotificationUserInfoKey.restoreFocus] as? Bool ?? false
            self?.hide(restoreFocus: restoreFocus)
        }
    }

    private func removeHidePanelObserver() {
        if let observer = hidePanelObserver {
            NotificationCenter.default.removeObserver(observer)
            hidePanelObserver = nil
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        focusSearchField()
    }

    func windowDidResignKey(_ notification: Notification) {
        // Skip auto-hide in test mode to allow XCUITest to interact with the panel
        guard !TestConfiguration.shouldDisablePanelAutoHide else { return }
        hide()
    }

    private func focusSearchField() {
        guard let panel = panel,
              let contentView = panel.contentView else { return }

        // Try to find and focus immediately
        if let textField = findTextField(in: contentView) {
            panel.makeFirstResponder(textField)
            return
        }

        // If not found, SwiftUI view hierarchy may not be ready yet.
        // Defer to next run loop to allow layout to complete.
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let panel = self.panel,
                  let contentView = panel.contentView else { return }

            if let textField = self.findTextField(in: contentView) {
                panel.makeFirstResponder(textField)
            } else {
                print("[PanelController] Warning: Could not find text field to focus")
            }
        }
    }

    private func findTextField(in view: NSView) -> NSTextField? {
        if let textField = view as? NSTextField, textField.isEditable {
            return textField
        }
        for subview in view.subviews {
            if let found = findTextField(in: subview) {
                return found
            }
        }
        return nil
    }

    deinit {
        stopKeyboardMonitor()
        removeHidePanelObserver()
    }
}
