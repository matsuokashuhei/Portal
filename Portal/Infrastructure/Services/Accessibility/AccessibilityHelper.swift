//
//  AccessibilityHelper.swift
//  Portal
//
//  Created by Claude Code on 2026/01/03.
//

import ApplicationServices
import AppKit

/// Utility functions for Accessibility API operations.
///
/// Provides common operations like retrieving element positions and sizes,
/// which are used by hint mode to display labels at element locations.
enum AccessibilityHelper {
    // MARK: - Constants

    /// Subroles that identify window control buttons (close, minimize, zoom, fullscreen).
    ///
    /// These buttons are handled specially because:
    /// - They don't have title attributes, so validation must check subrole instead
    /// - They often don't respond to AXPress, so mouse click is used as fallback
    static let windowControlSubroles: Set<String> = [
        "AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton"
    ]

    protocol FocusedElementProviding {
        func focusedElement() -> AXUIElement?
        func role(for element: AXUIElement) -> String?
    }

    struct SystemFocusedElementProvider: FocusedElementProviding {
        func focusedElement() -> AXUIElement? {
            let systemWide = AXUIElementCreateSystemWide()
            var focusedRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                systemWide,
                kAXFocusedUIElementAttribute as CFString,
                &focusedRef
            ) == .success,
                  let focusedRef else {
                return nil
            }
            // swiftlint:disable:next force_cast
            return focusedRef as! AXUIElement
        }

        func role(for element: AXUIElement) -> String? {
            AccessibilityHelper.getRoleOfFocusedElement(element)
        }
    }

    // MARK: - Element Identification

    /// Builds a readable identifier for an accessibility element.
    ///
    /// The identifier is stable for the lifetime of the AXUIElement instance and
    /// unique within the target application's process.
    /// Format: "<pid>-0x<pointer>" (e.g., "1234-0x10afc1").
    static func elementIdentifier(_ element: AXUIElement) -> String {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let pointerValue = UInt(bitPattern: Unmanaged.passUnretained(element).toOpaque())
        return "\(pid)-0x\(String(pointerValue, radix: 16))"
    }

    // MARK: - Frame Methods

    /// Retrieves the screen frame of an accessibility element.
    ///
    /// - Parameter element: The accessibility element to get the frame for.
    /// - Returns: The element's frame in screen coordinates (AppKit: bottom-left origin),
    ///            or `nil` if the position or size cannot be retrieved.
    ///
    /// - Note: The Accessibility API uses top-left origin coordinates.
    ///   This method converts to AppKit's bottom-left origin coordinate system.
    static func getFrame(_ element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        // Get position attribute
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionRef
        ) == .success else {
            return nil
        }

        // Get size attribute
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeRef
        ) == .success else {
            return nil
        }

        // Convert to CGPoint and CGSize
        var position = CGPoint.zero
        var size = CGSize.zero

        guard let positionValue = positionRef,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              AXValueGetValue(positionValue as! AXValue, .cgPoint, &position) else {
            return nil
        }

        guard let sizeValue = sizeRef,
              CFGetTypeID(sizeValue) == AXValueGetTypeID(),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }

        // Create rect in Accessibility coordinates (top-left origin)
        let axRect = CGRect(origin: position, size: size)

        // Convert to screen coordinates (bottom-left origin)
        return convertToScreenCoordinates(axRect)
    }

    /// Retrieves the screen frame of an accessibility element with fallback.
    ///
    /// If the element's frame cannot be retrieved directly, this method attempts
    /// to estimate a position based on the parent element's frame. This is useful
    /// for elements that don't expose their position through standard attributes.
    ///
    /// - Parameter element: The accessibility element to get the frame for.
    /// - Returns: The element's frame, a parent-based estimate, or `nil` if unavailable.
    static func getFrameWithFallback(_ element: AXUIElement) -> CGRect? {
        // First, try to get the frame directly
        if let frame = getFrame(element) {
            return frame
        }

        // Fallback: estimate position from parent element
        if let parent = getParent(element),
           let parentFrame = getFrame(parent),
           parentFrame.width > 0, parentFrame.height > 0 {
            // Use top-left corner of parent with a small default size
            // This isn't perfectly accurate but allows the hint to be displayed
            // Note: In AppKit coordinates (bottom-left origin), top-left is (minX, maxY - height)
            let width = min(parentFrame.width, 20)
            let height = min(parentFrame.height, 20)
            return CGRect(
                x: parentFrame.minX,
                y: parentFrame.maxY - height,
                width: width,
                height: height
            )
        }

        return nil
    }

    /// Converts a rect from Accessibility API coordinates to AppKit screen coordinates.
    ///
    /// The Accessibility API uses a coordinate system with the origin at the top-left
    /// of the primary screen. AppKit uses a coordinate system with the origin at the
    /// bottom-left of the primary screen.
    ///
    /// - Parameter axRect: A rect in Accessibility API coordinates (top-left origin).
    /// - Returns: The rect in AppKit screen coordinates (bottom-left origin).
    static func convertToScreenCoordinates(_ axRect: CGRect) -> CGRect {
        guard let primaryScreen = NSScreen.screens.first else {
            return axRect
        }

        let screenHeight = primaryScreen.frame.height

        // Flip Y coordinate: bottom = screenHeight - top - height
        let convertedY = screenHeight - axRect.origin.y - axRect.size.height

        return CGRect(
            x: axRect.origin.x,
            y: convertedY,
            width: axRect.size.width,
            height: axRect.size.height
        )
    }

    /// Checks if an accessibility element is visible on screen.
    ///
    /// - Parameter element: The element to check.
    /// - Returns: `true` if the element has a valid position and size, `false` otherwise.
    static func isVisible(_ element: AXUIElement) -> Bool {
        guard let frame = getFrame(element) else { return false }
        return frame.width > 0 && frame.height > 0
    }

    /// Gets the title of an accessibility element.
    ///
    /// - Parameter element: The element to get the title from.
    /// - Returns: The title string, or `nil` if not available.
    static func getTitle(_ element: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXTitleAttribute as CFString,
            &titleRef
        ) == .success,
              let title = titleRef as? String else {
            return nil
        }
        return title
    }


    /// Gets the AXLabel attribute from an accessibility element.
    /// This is different from the title: some elements (like Xcode's toggle buttons)
    /// have an empty title but a populated label.
    static func getLabel(_ element: AXUIElement) -> String? {
        var labelRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXLabel" as CFString, &labelRef) == .success,
           let label = labelRef as? String, !label.isEmpty else {
            return nil
        }
        return label
    }
    
    static func getIsEnabled(_ element: AXUIElement) -> Bool {
        var enabledRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabledRef) == .success else {
            return true  // Default to enabled if we can't determine
        }
        return (enabledRef as? Bool) ?? true
    }

    static func getAttributeValueAsString(_ element: AXUIElement, attribute: String) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef) == .success else {
            return nil
        }
        return valueRef as? String
    }
    
    /// Gets the role of an accessibility element.
    /// https://developer.apple.com/documentation/applicationservices/kaxroledescriptionattribute
    ///
    /// - Parameter element: The element to get the role from.
    /// - Returns: The role string (e.g., "AXButton"), or `nil` if not available.
    static func getRole(_ element: AXUIElement) -> String? {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &roleRef
        ) == .success,
              let role = roleRef as? String else {
            return nil
        }
        return role
    }

    static func getMainWindow(_ app: NSRunningApplication) -> AXUIElement? {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var mainWindowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp,
            kAXFocusedWindowAttribute as CFString,
            &mainWindowRef
        ) == .success else {
            return nil
        }
        // swiftlint:disable:next force_cast
        let mainWindow = mainWindowRef as! AXUIElement
        return mainWindow

    }

    /// Gets the main window frame of an application.
    ///
    /// - Parameter app: The running application to get the main window frame from.
    /// - Returns: The main window's frame in screen coordinates, or `nil` if unavailable.
    static func getMainWindowFrame(_ app: NSRunningApplication) -> CGRect? {
        guard let mainWindow = getMainWindow(app) else { return nil }
        return getFrame(mainWindow)
    }

    /// Gets frames for all windows of an application.
    ///
    /// This includes main window, popup menus, floating panels, and dialogs.
    ///
    /// - Parameter app: The running application to get window frames from.
    /// - Returns: Array of window frames in screen coordinates.
    static func getAllWindowFrames(_ app: NSRunningApplication) -> [CGRect] {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var frames: [CGRect] = []

        // Get all windows
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            axApp,
            kAXWindowsAttribute as CFString,
            &windowsRef
        ) == .success, let windows = windowsRef as? [AXUIElement] {
            for window in windows {
                if let frame = getFrame(window) {
                    frames.append(frame)
                }
            }
        }

        // Also check focused window (may include popups not in windows list)
        var focusedWindowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            axApp,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowRef
        ) == .success {
            // swiftlint:disable:next force_cast
            let focusedWindow = focusedWindowRef as! AXUIElement
            if let focusedFrame = getFrame(focusedWindow) {
                // Add if not already in frames
                if !frames.contains(where: { $0 == focusedFrame }) {
                    frames.append(focusedFrame)
                }
            }
        }

        // Fallback to main window if no windows found
        if frames.isEmpty {
            if let mainFrame = getMainWindowFrame(app) {
                frames.append(mainFrame)
            }
        }

        return frames
    }

    /// Gets the parent element of an accessibility element.
    ///
    /// - Parameter element: The element to get the parent from.
    /// - Returns: The parent element, or `nil` if not available.
    static func getParent(_ element: AXUIElement) -> AXUIElement? {
        var parentRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXParentAttribute as CFString,
            &parentRef
        ) == .success else {
            return nil
        }
        // swiftlint:disable:next force_cast
        return (parentRef as! AXUIElement)
    }

    /// Gets the children of an accessibility element.
    /// https://developer.apple.com/documentation/applicationservices/kaxchildrenattribute
    ///
    /// - Parameter element: The element to get children from.
    /// - Returns: Array of child elements, or empty array if not available.
    static func getChildren(_ element: AXUIElement) -> [AXUIElement] {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenRef
        ) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return []
        }
        return children
    }

    /// Checks if a text input element currently has focus.
    ///
    /// Uses the system-wide focused element to determine if the user is
    /// typing in a text input field. This is used to disable hotkeys
    /// and scroll mode during text input.
    ///
    /// - Returns: `true` if a text input element (AXTextField, AXTextArea, etc.) has focus.
    ///
    /// - Note: This method is `nonisolated` to allow calling from CGEventTap callbacks
    ///   which run on the main thread but outside the MainActor isolation context.
    nonisolated static func isTextInputElementFocused() -> Bool {
        isTextInputElementFocused(using: SystemFocusedElementProvider())
    }

    nonisolated static func isTextInputElementFocused(using provider: FocusedElementProviding) -> Bool {
        guard let focused = provider.focusedElement(),
              let role = provider.role(for: focused) else {
            return false
        }
        return ScrollConfiguration.textInputRoles.contains(role)
    }

    /// Returns the role of the currently focused UI element (system-wide), if available.
    ///
    /// This is used for debugging hotkey suppression (e.g., when focus is AXSearchField).
    nonisolated static func focusedElementRole() -> String? {
        focusedElementRole(using: SystemFocusedElementProvider())
    }

    nonisolated static func focusedElementRole(using provider: FocusedElementProviding) -> String? {
        guard let focused = provider.focusedElement() else {
            return nil
        }
        return provider.role(for: focused)
    }

    nonisolated private static func getRoleOfFocusedElement(_ focused: AXUIElement) -> String? {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused,
            kAXRoleAttribute as CFString,
            &roleRef
        ) == .success,
              let role = roleRef as? String else {
            return nil
        }
        return role
    }

    /// Gets the value attribute of an accessibility element.
    ///
    /// - Parameter element: The element to get the value from.
    /// - Returns: The value string, or `nil` if not available.
    static func getValue(_ element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueRef
        ) == .success,
              let value = valueRef as? String else {
            return nil
        }
        return value
    }

    /// Searches uncle elements (grandparent's children) for a title.
    ///
    /// This handles cases like System Settings tables where:
    /// ```
    /// AXRow (grandparent)
    /// ├── AXCell (label cell) > AXStaticText "App Store"  ← title is here
    /// └── AXCell (toggle cell) > AXSwitch                 ← we're here
    /// ```
    ///
    /// - Parameters:
    ///   - parent: The parent element (e.g., AXCell containing the switch).
    ///   - skipElement: The element to skip when searching (the parent itself).
    /// - Returns: The title found in uncle elements, or `nil` if not found.
    static func getTitleFromUncles(parent: AXUIElement, skipElement: AXUIElement) -> String? {
        guard let grandparent = getParent(parent) else {
            return nil
        }

        let uncles = getChildren(grandparent)

        for uncle in uncles {
            // Skip the parent cell itself
            if CFEqual(uncle, skipElement) {
                continue
            }

            guard let uncleRole = getRole(uncle) else {
                continue
            }

            // Direct AXStaticText under grandparent
            if uncleRole == "AXStaticText" {
                if let value = getValue(uncle), !value.isEmpty {
                    return value
                }
                if let title = getTitle(uncle), !title.isEmpty {
                    return title
                }
            }
            // Check uncle's children for AXStaticText (e.g., AXCell > AXStaticText)
            else if uncleRole == "AXCell" || uncleRole == "AXGroup" {
                let uncleChildren = getChildren(uncle)
                for uncleChild in uncleChildren {
                    if let childRole = getRole(uncleChild), childRole == "AXStaticText" {
                        if let value = getValue(uncleChild), !value.isEmpty {
                            return value
                        }
                        if let title = getTitle(uncleChild), !title.isEmpty {
                            return title
                        }
                    }
                }
            }
        }

        return nil
    }
}
