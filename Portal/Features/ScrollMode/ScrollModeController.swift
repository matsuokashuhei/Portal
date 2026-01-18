//
//  ScrollModeController.swift
//  Portal
//
//  Created by Claude Code on 2026/01/11.
//

import AppKit
import ApplicationServices
import CoreGraphics
import Logging

private let logger = PortalLogger.make("Portal", category: "ScrollModeController")

/// Controls Vimium-style keyboard scrolling.
///
/// This controller intercepts h/j/k/l key presses globally and translates them
/// into scroll events for the active window. It operates independently of hint mode
/// and is always active when accessibility permission is granted.
///
/// Key bindings:
/// - h: scroll left
/// - j: scroll down
/// - k: scroll up
/// - l: scroll right
@MainActor
final class ScrollModeController {
    // MARK: - Singleton

    /// The shared instance of the scroll mode controller.
    static let shared = ScrollModeController()

    // MARK: - State

    /// Whether scroll mode is currently running.
    private(set) var isRunning: Bool = false

    /// The CGEventTap for intercepting keyboard events.
    /// Using nonisolated(unsafe) because this is accessed from the event tap callback
    /// which runs on a different thread, but is only modified on MainActor.
    nonisolated(unsafe) private var eventTap: CFMachPort?

    /// The run loop source for the event tap.
    private var runLoopSource: CFRunLoopSource?

    // MARK: - Dependencies

    /// The executor for performing scroll actions.
    private let executor = ScrollExecutor()

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Starts the scroll mode controller.
    ///
    /// Sets up a CGEventTap to intercept scroll-related key events globally.
    /// Should be called when accessibility permission is granted.
    func start() {
        guard !isRunning else {
            #if DEBUG
            logger.debug("Already running")
            #endif
            return
        }

        startEventTap()
        isRunning = true

        #if DEBUG
        logger.info("Started")
        #endif
    }

    /// Stops the scroll mode controller.
    ///
    /// Removes the CGEventTap and cleans up resources.
    func stop() {
        guard isRunning else { return }

        stopEventTap()
        isRunning = false

        #if DEBUG
        logger.info("Stopped")
        #endif
    }

    // MARK: - Event Tap

    /// Sets up the CGEventTap to intercept keyboard events.
    private func startEventTap() {
        let eventMask = (1 << CGEventType.keyDown.rawValue)

        // Pass self as userInfo to access in the callback
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else {
                    return Unmanaged.passRetained(event)
                }

                // Handle tap disabled event (system may disable the tap)
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    let controller = Unmanaged<ScrollModeController>.fromOpaque(userInfo).takeUnretainedValue()
                    if let tap = controller.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passRetained(event)
                }

                let controller = Unmanaged<ScrollModeController>.fromOpaque(userInfo).takeUnretainedValue()

                // Get event details
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags

                // Check if this is a scroll key we should handle
                // Must be called synchronously to determine event consumption
                let shouldConsume = controller.shouldConsumeEvent(keyCode: keyCode, flags: flags)

                if shouldConsume {
                    // Dispatch the actual scroll action to MainActor
                    Task { @MainActor in
                        controller.handleKeyEvent(keyCode: keyCode)
                    }
                    // Consume the event (return nil)
                    return nil
                }

                // Pass through non-scroll events
                return Unmanaged.passRetained(event)
            },
            userInfo: userInfo
        ) else {
            #if DEBUG
            logger.warning("Failed to create CGEventTap")
            #endif
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)

        #if DEBUG
        logger.debug("CGEventTap started successfully")
        #endif
    }

    /// Removes the CGEventTap.
    private func stopEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }

        #if DEBUG
        logger.debug("CGEventTap stopped")
        #endif
    }

    // MARK: - Event Handling

    /// Determines whether to consume (intercept) a key event.
    ///
    /// This method is called synchronously from the event tap callback
    /// to determine whether the event should be consumed.
    ///
    /// - Parameters:
    ///   - keyCode: The Carbon key code of the pressed key.
    ///   - flags: The modifier flags of the event.
    /// - Returns: `true` if the event should be consumed, `false` otherwise.
    private nonisolated func shouldConsumeEvent(keyCode: Int64, flags: CGEventFlags) -> Bool {
        // Don't intercept if modifier keys (other than Shift) are pressed
        // This allows Command+J, Control+K, etc. to work normally
        let modifiersExceptShift: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
        if !flags.intersection(modifiersExceptShift).isEmpty {
            return false
        }

        // Check if it's a scroll key
        guard ScrollKey.from(keyCode: keyCode) != nil else {
            return false
        }

        // Check if hint mode is active (don't interfere with hint mode)
        // Note: This is a cross-thread read, but isActive is only written on MainActor
        // and is a simple Bool, so the worst case is a stale read which is acceptable.
        if HintModeController.shared.isActive {
            return false
        }

        // Check if a text field has focus (allow normal text input)
        if AccessibilityHelper.isTextInputElementFocused() {
            return false
        }

        return true
    }

    /// Handles a scroll key event.
    ///
    /// - Parameter keyCode: The Carbon key code of the pressed key.
    private func handleKeyEvent(keyCode: Int64) {
        guard let scrollKey = ScrollKey.from(keyCode: keyCode) else { return }

        // Execute scroll action
        switch scrollKey {
        case .h: executor.scroll(direction: .left)
        case .j: executor.scroll(direction: .down)
        case .k: executor.scroll(direction: .up)
        case .l: executor.scroll(direction: .right)
        }
    }

}
