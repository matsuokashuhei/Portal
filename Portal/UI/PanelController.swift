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
    static let panelSize = NSSize(width: 600, height: 400)

    private var panel: NSPanel?
    private var escapeMonitor: Any?
    private var hasBeenPositioned = false

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
        stopEscapeMonitor()
        startEscapeMonitor()

        // Post notification with target app info
        var userInfo: [String: Any] = [:]
        if let app = targetApp {
            userInfo[NotificationUserInfoKey.targetApp] = app
        }
        NotificationCenter.default.post(name: .panelDidShow, object: nil, userInfo: userInfo.isEmpty ? nil : userInfo)
    }

    func hide() {
        stopEscapeMonitor()
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

    private func startEscapeMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == Self.escapeKeyCode && modifiers.isEmpty {
                self?.hide()
                return nil
            }
            return event
        }
    }

    private func stopEscapeMonitor() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
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
        stopEscapeMonitor()
    }
}
