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

    static let panelSize = NSSize(width: 600, height: 400)

    private var panel: NSPanel?
    private var keyboardMonitor: Any?
    private var hasBeenPositioned = false
    private var hidePanelObserver: NSObjectProtocol?

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

    func hide() {
        stopKeyboardMonitor()
        removeHidePanelObserver()
        panel?.orderOut(nil)
        panel = nil
        hasBeenPositioned = false
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

            // Only handle keys without modifiers
            guard modifiers.isEmpty else { return event }

            switch event.keyCode {
            case Self.escapeKeyCode:
                self?.hide()
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
        ) { [weak self] _ in
            self?.hide()
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
