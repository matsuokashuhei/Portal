//
//  HintOverlayWindow.swift
//  Portal
//
//  Created by Claude Code on 2026/01/03.
//

import AppKit
import SwiftUI

/// A transparent overlay window that displays hint labels over the target application.
///
/// This window covers the entire screen and shows hint labels at the positions
/// of interactive UI elements. It passes through mouse events and only captures
/// keyboard input for hint selection.
final class HintOverlayWindow: NSWindow {
    /// The hint labels being displayed.
    private var hints: [HintLabel]

    /// The current user input for filtering hints.
    private var currentInput: String = ""

    /// The hosting view for SwiftUI content.
    private var hostingView: NSHostingView<HintOverlayView>?

    /// Creates an overlay window for displaying hint labels.
    ///
    /// - Parameters:
    ///   - hints: The hint labels to display.
    ///   - screen: The screen to display the overlay on.
    init(hints: [HintLabel], on screen: NSScreen) {
        self.hints = hints

        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        setupWindow()
        setupContent(screen: screen)
    }

    /// Configures the window properties for overlay display.
    private func setupWindow() {
        // Window level above popup menus and floating windows
        // Use popUpMenu level + 1 to ensure hints appear above context menus
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1)

        // Transparent background
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false

        // Pass through mouse events
        ignoresMouseEvents = true

        // Appear on all spaces and work with fullscreen apps
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // Don't show in Dock or Mission Control
        isExcludedFromWindowsMenu = true

        // Prevent automatic release when closed to avoid dangling references
        isReleasedWhenClosed = false
    }

    deinit {
        #if DEBUG
        print("[HintOverlayWindow] deinit")
        #endif
    }

    /// Sets up the SwiftUI content view.
    private func setupContent(screen: NSScreen) {
        let overlayView = HintOverlayView(
            hints: hints,
            currentInput: currentInput,
            screenBounds: screen.frame
        )

        hostingView = NSHostingView(rootView: overlayView)
        contentView = hostingView
    }

    /// Updates the visible hints based on user input.
    ///
    /// - Parameter input: The current user input string.
    func updateVisibleHints(for input: String) {
        currentInput = input

        guard let screen = screen else { return }

        let updatedView = HintOverlayView(
            hints: hints,
            currentInput: currentInput,
            screenBounds: screen.frame
        )
        hostingView?.rootView = updatedView
    }

    /// Dismisses the overlay window.
    func dismiss() {
        #if DEBUG
        print("[HintOverlayWindow] dismiss called")
        #endif

        // Clear content view to release SwiftUI hosting view
        contentView = nil
        hostingView = nil

        orderOut(nil)
    }

    /// Shows the overlay window.
    func show() {
        // Use orderFrontRegardless instead of makeKeyAndOrderFront
        // because this window cannot become key (ignoresMouseEvents = true)
        orderFrontRegardless()
    }

    // MARK: - NSWindow Overrides

    /// Returns false because this overlay window should not become key.
    /// Keyboard input is captured via global event monitoring instead.
    override var canBecomeKey: Bool {
        false
    }
}

// MARK: - Multi-Screen Support

extension HintOverlayWindow {
    /// Creates overlay windows for all screens.
    ///
    /// - Parameter hints: The hint labels to display.
    /// - Returns: An array of overlay windows, one for each screen.
    static func createForAllScreens(hints: [HintLabel]) -> [HintOverlayWindow] {
        NSScreen.screens.map { screen in
            // Filter hints to only those visible on this screen
            let screenHints = hints.filter { hint in
                screen.frame.intersects(hint.frame)
            }
            return HintOverlayWindow(hints: screenHints, on: screen)
        }
    }
}
