//
//  HotkeyManager.swift
//  Portal
//
//  Created by Claude Code on 2025/12/30.
//

import AppKit
import Carbon.HIToolbox

final class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var localMonitor: Any?
    private var fallbackMonitor: Any?
    private let onHotkeyPressed: () -> Void

    /// Configurable hotkey combination (modifier + key)
    private let configuration: HotkeyConfiguration

    /// Configuration for apps where the hotkey should be disabled
    private let excludedAppsConfiguration: ExcludedAppsConfiguration

    init(
        configuration: HotkeyConfiguration = .load(),
        excludedAppsConfiguration: ExcludedAppsConfiguration = .load(),
        onHotkeyPressed: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.excludedAppsConfiguration = excludedAppsConfiguration
        self.onHotkeyPressed = onHotkeyPressed
    }

    func start() {
        startEventTap()
        startLocalMonitor()
    }

    func stop() {
        stopEventTap()
        stopLocalMonitor()
        stopFallbackMonitor()
    }

    // MARK: - CGEventTap (Global Hotkey with Event Consumption)

    /// Starts a CGEventTap to intercept and consume global hotkey events.
    ///
    /// Unlike `addGlobalMonitorForEvents`, CGEventTap can actually consume events,
    /// preventing them from being delivered to other applications. This is necessary
    /// to prevent the configured hotkey from triggering system shortcuts (e.g., Quick Look).
    ///
    /// ## Fallback Behavior
    /// If CGEventTap creation fails (typically when Accessibility permission is not granted),
    /// we fall back to `addGlobalMonitorForEvents` which CANNOT consume events. In this case:
    /// - Portal will still respond to the configured hotkey
    /// - System shortcuts may also trigger simultaneously
    /// - Once the user grants Accessibility permission and relaunches Portal, CGEventTap will work
    private func startEventTap() {
        // Create callback that will be called for each keyboard event
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }

            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

            // Handle tap being disabled by the system (e.g., due to timeout)
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = manager.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            // Only handle key down events
            guard type == .keyDown else {
                return Unmanaged.passUnretained(event)
            }

            // Check if this is our configured hotkey
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags

            // Check for the configured modifier (without other modifiers)
            let targetMask = manager.configuration.modifier.cgEventMask
            let allModifierMasks: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

            let isMatch: Bool
            if manager.configuration.modifier.isNone {
                // No modifier required - check that NO modifiers are pressed
                let hasAnyModifier = !flags.intersection(allModifierMasks).isEmpty
                isMatch = !hasAnyModifier && keyCode == manager.configuration.key.keyCode
            } else {
                // Standard modifier-based hotkey
                let otherMasks = allModifierMasks.subtracting(targetMask)
                let hasTargetModifier = flags.contains(targetMask)
                let hasOtherModifiers = !flags.intersection(otherMasks).isEmpty
                isMatch = hasTargetModifier && !hasOtherModifiers && keyCode == manager.configuration.key.keyCode
            }

            if isMatch {
                // Check if the frontmost app is excluded
                if manager.shouldSkipForFrontmostApp() {
                    return Unmanaged.passUnretained(event)
                }

                // Dispatch callback to main thread
                DispatchQueue.main.async {
                    manager.onHotkeyPressed()
                }
                // Return nil to consume the event (prevent it from reaching other apps)
                return nil
            }

            return Unmanaged.passUnretained(event)
        }

        // Create the event tap
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: refcon
        ) else {
            // Fall back to global monitor if event tap fails (e.g., no accessibility permission)
            #if DEBUG
            print("[HotkeyManager] CGEventTap creation failed, falling back to global monitor")
            #endif
            startGlobalMonitorFallback()
            return
        }

        eventTap = tap

        // Create a run loop source and add it to the current run loop
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        // Enable the event tap
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Stops and cleans up the CGEventTap.
    ///
    /// ## Thread Safety
    /// This method must be called on the main thread (where the event tap was created).
    /// The CGEventTap callback runs on the thread that owns the run loop to which the tap
    /// is added (CFRunLoopGetCurrent() in startEventTap(), which is the main run loop).
    /// Disabling the tap with `CGEvent.tapEnable` ensures no callbacks are in progress
    /// or will occur after this call returns, making it safe for the callback's
    /// unretained reference to be invalidated during deinit.
    private func stopEventTap() {
        if let tap = eventTap {
            // Disable tap first to prevent new callbacks
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            // CFMachPort will be released when eventTap is set to nil
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// Fallback to global monitor if CGEventTap fails.
    /// Note: This cannot consume events, so Quick Look may still trigger.
    private func startGlobalMonitorFallback() {
        // This is kept as a fallback but won't consume the event
        fallbackMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            // Check if the frontmost app is excluded
            if self.shouldSkipForFrontmostApp() {
                return
            }
            if self.isHotkeyEvent(event) {
                self.onHotkeyPressed()
            }
        }
    }

    private func stopFallbackMonitor() {
        if let monitor = fallbackMonitor {
            NSEvent.removeMonitor(monitor)
            fallbackMonitor = nil
        }
    }

    // MARK: - Local Monitor (For When Portal is Frontmost)

    private func startLocalMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if self.isHotkeyEvent(event) {
                self.onHotkeyPressed()
                return nil
            }
            return event
        }
    }

    private func stopLocalMonitor() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    // MARK: - Helper

    /// Checks if the frontmost application is in the exclusion list.
    ///
    /// This method is safe to call from CGEventTap callback as it runs on the main thread
    /// (the tap is added to the main run loop via CFRunLoopGetCurrent()).
    private func shouldSkipForFrontmostApp() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = frontmostApp.bundleIdentifier else {
            return false
        }
        return excludedAppsConfiguration.isExcluded(bundleIdentifier: bundleIdentifier)
    }

    private func isHotkeyEvent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let targetModifier = configuration.modifier.eventModifier
        // Use Int64 for consistency with CGEventTap callback comparison
        let keyMatches = Int64(event.keyCode) == configuration.key.keyCode

        if configuration.modifier.isNone {
            // No modifier required - check that NO modifiers are pressed
            return modifiers.isEmpty && keyMatches
        } else {
            return modifiers == targetModifier && keyMatches
        }
    }

    deinit {
        stop()
    }
}
