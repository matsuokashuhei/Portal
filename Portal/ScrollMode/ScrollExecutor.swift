//
//  ScrollExecutor.swift
//  Portal
//
//  Created by Claude Code on 2026/01/11.
//

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

        // Post the event to the HID event tap (applies to active window)
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
}
