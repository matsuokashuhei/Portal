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

    /// Retrieves frames for multiple accessibility elements.
    ///
    /// - Parameter elements: The accessibility elements to get frames for.
    /// - Returns: An array of frames. Elements whose frames cannot be retrieved
    ///            will have `.zero` as their frame.
    static func getFrames(_ elements: [AXUIElement]) -> [CGRect] {
        elements.map { getFrame($0) ?? .zero }
    }

    /// Converts a rect from Accessibility API coordinates to AppKit screen coordinates.
    ///
    /// The Accessibility API uses a coordinate system with the origin at the top-left
    /// of the primary screen. AppKit uses a coordinate system with the origin at the
    /// bottom-left of the primary screen.
    ///
    /// - Parameter axRect: A rect in Accessibility API coordinates (top-left origin).
    /// - Returns: The rect in AppKit screen coordinates (bottom-left origin).
    private static func convertToScreenCoordinates(_ axRect: CGRect) -> CGRect {
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

    /// Gets the role of an accessibility element.
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

    /// Gets the main window frame of an application.
    ///
    /// - Parameter app: The running application to get the main window frame from.
    /// - Returns: The main window's frame in screen coordinates, or `nil` if unavailable.
    static func getMainWindowFrame(_ app: NSRunningApplication) -> CGRect? {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var mainWindowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp,
            kAXMainWindowAttribute as CFString,
            &mainWindowRef
        ) == .success else {
            return nil
        }

        // swiftlint:disable:next force_cast
        let mainWindow = mainWindowRef as! AXUIElement
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

    /// Checks if an element is visible within all its parent scroll containers.
    ///
    /// Elements inside scroll areas may have valid frames but be scrolled out of view.
    /// This method walks up the parent hierarchy and checks if the element's frame
    /// intersects with any parent AXScrollArea's visible bounds.
    ///
    /// - Parameter element: The element to check visibility for.
    /// - Returns: `true` if the element is visible in all parent scroll containers,
    ///            `false` if it's scrolled out of view.
    static func isVisibleInScrollContainers(_ element: AXUIElement) -> Bool {
        guard let elementFrame = getFrame(element) else { return false }

        // Walk up parent hierarchy checking for scroll containers
        var current = element
        while let parent = getParent(current) {
            if let role = getRole(parent), role == "AXScrollArea" {
                if let parentFrame = getFrame(parent) {
                    // Element must intersect with scroll area's visible bounds
                    if !parentFrame.intersects(elementFrame) {
                        return false
                    }
                }
            }
            current = parent
        }
        return true
    }

    /// Gets the parent element of an accessibility element.
    ///
    /// - Parameter element: The element to get the parent from.
    /// - Returns: The parent element, or `nil` if not available.
    private static func getParent(_ element: AXUIElement) -> AXUIElement? {
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
}
