//
//  ScrollExecutor.swift
//  Portal
//
//  Created by Claude Code on 2026/01/11.
//

import AppKit
import CoreGraphics

/// Executes scroll actions by generating CGEvent scroll wheel events.
///
/// Uses `CGEventCreateScrollWheelEvent2` to create pixel-based scroll events
/// that simulate mouse wheel scrolling. This approach works with most
/// applications regardless of their scrolling implementation.
@MainActor
final class ScrollExecutor {
    // MARK: - Public Methods

    /// Scrolls in the specified direction.
    ///
    /// - Parameter direction: The direction to scroll.
    func scroll(direction: ScrollDirection) {
        let (deltaX, deltaY) = calculateDelta(for: direction)

        // Create a scroll wheel event with 2 wheels (vertical and horizontal)
        // Using pixel units for smooth scrolling
        // wheel1 = vertical, wheel2 = horizontal, wheel3 = unused (set to 0)
        guard let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        ) else {
            #if DEBUG
            print("[ScrollExecutor] Failed to create scroll event")
            #endif
            return
        }

        // Set the event location to the center of the active window.
        // Without this, scroll events are sent to the window under the mouse cursor,
        // which may be a different app than the frontmost one.
        if let location = getActiveWindowCenter() {
            scrollEvent.location = location
            #if DEBUG
            print("[ScrollExecutor] Scroll location set to \(location)")
            #endif
        }

        // Post the event to the HID event tap
        scrollEvent.post(tap: .cghidEventTap)

        #if DEBUG
        print("[ScrollExecutor] Scroll \(direction) (deltaX: \(deltaX), deltaY: \(deltaY))")
        #endif
    }

    // MARK: - Private Methods

    /// Calculates the delta values for a scroll direction.
    ///
    /// - Parameter direction: The direction to scroll.
    /// - Returns: A tuple of (deltaX, deltaY) values.
    ///
    /// Note: Positive deltaY scrolls up (content moves down), negative scrolls down.
    /// Positive deltaX scrolls left (content moves right), negative scrolls right.
    private func calculateDelta(for direction: ScrollDirection) -> (Int32, Int32) {
        switch direction {
        case .up:       return (0, ScrollConfiguration.scrollAmount)
        case .down:     return (0, -ScrollConfiguration.scrollAmount)
        case .left:     return (ScrollConfiguration.scrollAmount, 0)
        case .right:    return (-ScrollConfiguration.scrollAmount, 0)
        case .toTop:    return (0, ScrollConfiguration.jumpScrollAmount)
        case .toBottom: return (0, -ScrollConfiguration.jumpScrollAmount)
        }
    }

    /// Gets the center point of the active (frontmost) application's main window.
    ///
    /// - Returns: The center point in CGEvent screen coordinates (top-left origin), or nil if unavailable.
    private func getActiveWindowCenter() -> CGPoint? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              frontmostApp.bundleIdentifier != Bundle.main.bundleIdentifier else {
            #if DEBUG
            print("[ScrollExecutor] No frontmost app or frontmost is Portal")
            #endif
            return nil
        }

        #if DEBUG
        print("[ScrollExecutor] Frontmost app: \(frontmostApp.localizedName ?? "unknown") (bundleID: \(frontmostApp.bundleIdentifier ?? "unknown"))")
        #endif

        guard let frame = AccessibilityHelper.getMainWindowFrame(frontmostApp) else {
            #if DEBUG
            print("[ScrollExecutor] Could not get main window frame for \(frontmostApp.localizedName ?? "unknown")")
            #endif
            return nil
        }

        #if DEBUG
        print("[ScrollExecutor] Main window frame (Accessibility coords, bottom-left origin): \(frame)")
        #endif

        // Convert from Accessibility coordinates (bottom-left origin) to
        // CGEvent coordinates (top-left origin).
        // Formula: cgEventY = screenHeight - accessibilityY
        guard let screenHeight = NSScreen.main?.frame.height else {
            #if DEBUG
            print("[ScrollExecutor] Could not get screen height")
            #endif
            return nil
        }

        let centerX = frame.midX
        let centerY = screenHeight - frame.midY

        #if DEBUG
        print("[ScrollExecutor] Screen height: \(screenHeight), Converted center: (\(centerX), \(centerY))")
        #endif

        return CGPoint(x: centerX, y: centerY)
    }
}
