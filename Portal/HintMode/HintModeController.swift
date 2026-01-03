//
//  HintModeController.swift
//  Portal
//
//  Created by Claude Code on 2026/01/03.
//

import AppKit
import ApplicationServices
import CoreGraphics

// MARK: - CGEvent Extension

extension CGEvent {
    /// Gets the characters from a keyboard event, ignoring modifiers.
    func keyboardEventCharactersIgnoringModifiers() -> String? {
        var length = 0
        keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)

        guard length > 0 else { return nil }

        var chars = [UniChar](repeating: 0, count: length)
        keyboardGetUnicodeString(maxStringLength: length, actualStringLength: &length, unicodeString: &chars)

        return String(utf16CodeUnits: chars, count: length)
    }
}

/// Controls the hint mode for keyboard navigation of UI elements.
///
/// The controller manages the lifecycle of hint mode, including:
/// - Crawling window elements from the target application
/// - Generating and displaying hint labels
/// - Processing keyboard input for element selection
/// - Executing the selected element
@MainActor
final class HintModeController {
    // MARK: - Singleton

    /// The shared instance of the hint mode controller.
    static let shared = HintModeController()

    // MARK: - State

    /// Whether hint mode is currently active.
    private(set) var isActive: Bool = false

    /// The overlay windows displaying hint labels.
    private var overlayWindows: [HintOverlayWindow] = []

    /// All hint labels being displayed.
    private var hints: [HintLabel] = []

    /// The current input buffer for label matching.
    private var inputBuffer: String = ""

    /// The target application being navigated.
    private var targetApp: NSRunningApplication?

    /// The CGEventTap for consuming keyboard events during hint mode.
    /// Using nonisolated(unsafe) because this is accessed from the event tap callback
    /// which runs on a different thread, but is only modified on MainActor.
    nonisolated(unsafe) private var eventTap: CFMachPort?

    /// The run loop source for the event tap.
    private var runLoopSource: CFRunLoopSource?

    /// Fallback keyboard monitor when CGEventTap is not available.
    private var keyboardMonitor: Any?

    /// Observer for application activation notifications.
    private var applicationActivationObserver: NSObjectProtocol?

    // MARK: - Dependencies

    /// The window crawler for retrieving UI elements.
    private let windowCrawler = WindowCrawler()

    /// The command executor for performing actions.
    private let commandExecutor = CommandExecutor()

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Activates hint mode for the specified application.
    ///
    /// - Parameter app: The application to navigate. If nil, uses the frontmost application.
    func activate(for app: NSRunningApplication? = nil) {
        guard !isActive else {
            #if DEBUG
            print("[HintModeController] Already active")
            #endif
            return
        }

        // Get target application (excluding Portal itself)
        targetApp = app ?? getFrontmostApp()
        guard let targetApp else {
            #if DEBUG
            print("[HintModeController] No target application")
            #endif
            return
        }

        #if DEBUG
        print("[HintModeController] Activating for \(targetApp.localizedName ?? "unknown")")
        #endif

        // Start the activation process
        Task {
            await performActivation(for: targetApp)
        }
    }

    /// Deactivates hint mode and dismisses the overlay.
    func deactivate() {
        guard isActive else { return }

        #if DEBUG
        print("[HintModeController] Deactivating")
        #endif

        // Stop keyboard monitoring
        stopKeyboardMonitor()

        // Stop observing application activation
        stopApplicationActivationObserver()

        // Dismiss overlay windows
        #if DEBUG
        print("[HintModeController] Dismissing \(overlayWindows.count) overlay windows")
        #endif
        for window in overlayWindows {
            window.dismiss()
        }
        overlayWindows.removeAll()
        #if DEBUG
        print("[HintModeController] Overlay windows cleared")
        #endif

        // Reset state
        hints.removeAll()
        inputBuffer = ""
        targetApp = nil
        isActive = false

        // Post notification
        NotificationCenter.default.post(name: .hintModeDidDeactivate, object: nil)
    }

    // MARK: - Private Methods

    /// Performs the async activation process.
    private func performActivation(for app: NSRunningApplication) async {
        do {
            // Crawl window elements
            let crawlResult = try await windowCrawler.crawlWindowElements(app)
            var items = crawlResult.items

            guard !items.isEmpty else {
                #if DEBUG
                print("[HintModeController] No window elements found")
                #endif
                return
            }

            #if DEBUG
            print("[HintModeController] Crawled \(items.count) items (isPopupMenu: \(crawlResult.isPopupMenu))")
            #endif

            // Filter items by window bounds ONLY for normal window crawling
            // Skip filtering for popup menus since they can extend beyond window bounds
            if !crawlResult.isPopupMenu {
                // Get all window frames for filtering (includes main window, popups, dialogs)
                let windowFrames = AccessibilityHelper.getAllWindowFrames(app)
                #if DEBUG
                print("[HintModeController] Found \(windowFrames.count) window frames")
                for (index, frame) in windowFrames.enumerated() {
                    print("[HintModeController] Window \(index): \(frame.debugDescription)")
                }
                #endif

                if !windowFrames.isEmpty {
                    items = items.filter { item in
                        guard let frame = AccessibilityHelper.getFrame(item.axElement) else {
                            return false
                        }
                        // Check if element is within ANY of the window bounds
                        let isInAnyWindow = windowFrames.contains { windowFrame in
                            windowFrame.contains(frame) || windowFrame.intersects(frame)
                        }
                        guard isInAnyWindow else {
                            return false
                        }
                        // Check visibility in scroll containers (filters out scrolled-out elements)
                        return AccessibilityHelper.isVisibleInScrollContainers(item.axElement)
                    }
                    #if DEBUG
                    print("[HintModeController] Filtered to \(items.count) items within window bounds and visible in scroll containers")
                    #endif
                }

                guard !items.isEmpty else {
                    #if DEBUG
                    print("[HintModeController] No items within window bounds")
                    #endif
                    return
                }
            }

            // Get frames for filtered elements
            let frames = items.map { AccessibilityHelper.getFrame($0.axElement) ?? .zero }

            // Create hint labels for filtered items only
            hints = HintLabelGenerator.createHintLabels(from: items, frames: frames)

            guard !hints.isEmpty else {
                #if DEBUG
                print("[HintModeController] No valid hints (all frames invalid)")
                #endif
                return
            }

            #if DEBUG
            print("[HintModeController] Created \(hints.count) hints")
            #endif

            // Create and show overlay windows
            guard let screen = NSScreen.main else { return }
            let overlayWindow = HintOverlayWindow(hints: hints, on: screen)
            overlayWindow.show()
            overlayWindows = [overlayWindow]

            // Start keyboard monitoring
            startKeyboardMonitor()

            // Start observing application activation to auto-deactivate when app switches
            startApplicationActivationObserver()

            isActive = true

            // Post notification
            NotificationCenter.default.post(name: .hintModeDidActivate, object: nil)

        } catch {
            #if DEBUG
            print("[HintModeController] Activation failed: \(error)")
            #endif
        }
    }

    /// Gets the frontmost application excluding Portal.
    private func getFrontmostApp() -> NSRunningApplication? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return nil
        }
        return frontmost
    }

    // MARK: - Keyboard Handling

    /// Starts monitoring keyboard events using CGEventTap.
    ///
    /// CGEventTap is used instead of `addGlobalMonitorForEvents` because:
    /// - Global monitors only observe events, they cannot consume them
    /// - This causes key events to reach the target app (e.g., pressing "B" selects Bluetooth in System Settings)
    /// - CGEventTap can intercept and consume events by returning nil from the callback
    private func startKeyboardMonitor() {
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
                    // Re-enable the tap if it was disabled
                    let controller = Unmanaged<HintModeController>.fromOpaque(userInfo).takeUnretainedValue()
                    if let tap = controller.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passRetained(event)
                }

                // Get the controller from userInfo
                let controller = Unmanaged<HintModeController>.fromOpaque(userInfo).takeUnretainedValue()

                // Process the key event on MainActor
                // Note: We process synchronously here to determine whether to consume the event
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let characters = event.keyboardEventCharactersIgnoringModifiers()

                // Dispatch to MainActor for state updates
                Task { @MainActor in
                    controller.handleKeyEvent(keyCode: keyCode, characters: characters)
                }

                // Consume the event (return nil) to prevent it from reaching the target app
                // ESC (53), Backspace (51), and letter keys are all consumed during hint mode
                let shouldConsume = keyCode == 53 || keyCode == 51 || (characters?.first?.isLetter == true)
                if shouldConsume {
                    return nil
                }

                // Pass through other events
                return Unmanaged.passRetained(event)
            },
            userInfo: userInfo
        ) else {
            #if DEBUG
            print("[HintModeController] Failed to create CGEventTap, falling back to global monitor")
            #endif
            // Fallback to global monitor (events won't be consumed)
            keyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                Task { @MainActor in
                    self?.handleKeyDown(event)
                }
            }
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)

        #if DEBUG
        print("[HintModeController] CGEventTap started successfully")
        #endif
    }

    /// Stops monitoring keyboard events.
    private func stopKeyboardMonitor() {
        // Stop CGEventTap
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }

        // Stop fallback monitor if used
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }

        #if DEBUG
        print("[HintModeController] Keyboard monitor stopped")
        #endif
    }

    /// Handles a key down event from NSEvent (fallback monitor).
    ///
    /// - Parameter event: The key event.
    private func handleKeyDown(_ event: NSEvent) {
        handleKeyEvent(keyCode: Int64(event.keyCode), characters: event.charactersIgnoringModifiers)
    }

    /// Handles a key event from CGEventTap or NSEvent.
    ///
    /// - Parameters:
    ///   - keyCode: The key code of the pressed key.
    ///   - characters: The characters generated by the key press (ignoring modifiers).
    private func handleKeyEvent(keyCode: Int64, characters: String?) {
        // ESC - deactivate
        if keyCode == 53 {
            deactivate()
            return
        }

        // Backspace - clear input
        if keyCode == 51 {
            if !inputBuffer.isEmpty {
                inputBuffer.removeLast()
                updateOverlay()
            }
            return
        }

        // Letter keys (A-Z)
        guard let characters = characters?.uppercased(),
              characters.count == 1,
              let char = characters.first,
              char.isLetter else {
            return
        }

        // Add to input buffer
        inputBuffer.append(char)

        // Check for match
        processInput()
    }

    /// Processes the current input to find matches.
    ///
    /// Uses Vimium-style matching: only executes when the input uniquely identifies
    /// a single hint. This allows multi-character labels (e.g., "AA") to be typed
    /// even when single-character labels (e.g., "A") exist.
    private func processInput() {
        // Filter hints that match the current input
        let filtered = HintLabelGenerator.filterHints(hints, by: inputBuffer)

        // No matches - reset input
        if filtered.isEmpty {
            #if DEBUG
            print("[HintModeController] No matches for '\(inputBuffer)', resetting")
            #endif
            inputBuffer = ""
            updateOverlay()
            return
        }

        // Exactly one match - execute
        if filtered.count == 1 {
            executeHint(filtered[0])
            return
        }

        // Multiple matches - update overlay and wait for more input
        #if DEBUG
        print("[HintModeController] Multiple matches (\(filtered.count)) for '\(inputBuffer)', waiting for more input")
        #endif
        updateOverlay()
    }

    /// Updates the overlay windows with the current input.
    private func updateOverlay() {
        for window in overlayWindows {
            window.updateVisibleHints(for: inputBuffer)
        }
    }

    /// Executes the action for the selected hint.
    ///
    /// - Parameter hint: The hint to execute.
    private func executeHint(_ hint: HintLabel) {
        #if DEBUG
        print("[HintModeController] Executing hint '\(hint.label)' for '\(hint.menuItem.title)'")
        #endif

        // Execute the command
        let result = commandExecutor.execute(hint.menuItem)

        switch result {
        case .success:
            #if DEBUG
            print("[HintModeController] Execution successful")
            #endif
        case .failure(let error):
            #if DEBUG
            print("[HintModeController] Execution failed: \(error)")
            #endif
        }

        // Deactivate after execution (success or failure)
        deactivate()
    }

    // MARK: - Application Activation Observation

    /// Starts observing application activation to auto-deactivate hint mode when the target app is deactivated.
    private func startApplicationActivationObserver() {
        // Note: NSWorkspace notifications are posted to NSWorkspace.shared.notificationCenter,
        // not NotificationCenter.default
        applicationActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, self.isActive else { return }

            // Get the newly activated application
            guard let userInfo = notification.userInfo,
                  let activatedApp = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }

            // Ensure we have a valid target application before comparing
            guard let targetApp = self.targetApp else { return }

            // If the activated app is different from our target, deactivate hint mode
            if activatedApp.processIdentifier != targetApp.processIdentifier {
                #if DEBUG
                print("[HintModeController] App switched to \(activatedApp.localizedName ?? "unknown"), deactivating")
                #endif
                self.deactivate()
            }
        }
    }

    /// Stops observing application activation.
    private func stopApplicationActivationObserver() {
        if let observer = applicationActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            applicationActivationObserver = nil
        }
    }
}
