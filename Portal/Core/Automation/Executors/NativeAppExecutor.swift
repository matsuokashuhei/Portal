//
//  NativeAppExecutor.swift
//  Portal
//
//  Created by Claude Code on 2026/01/12.
//

import ApplicationServices
import AppKit
import Logging

private let logger = PortalLogger.make("Portal", category: "NativeAppExecutor")

/// Executor for native macOS applications using standard Accessibility API.
///
/// This executor handles native macOS applications that have stable AXUIElement references
/// and respond well to AXPress, AXSelect, and other standard accessibility actions.
///
/// ## Responsibilities
/// - Execute actions via Accessibility API (AXPress, AXSelect, etc.)
/// - Handle text fields, sliders, checkboxes, and other native controls
/// - Validate elements before execution
///
/// ## Thread Safety
/// All methods must be called on the main thread due to Accessibility API requirements.
@MainActor
final class NativeAppExecutor: ActionExecutor {

    // MARK: - Role Definitions

    /// Valid accessibility roles for native macOS applications.
    static let validRoles: Set<String> = [
        "AXRow", "AXCell", "AXOutlineRow", "AXStaticText", "AXButton", "AXRadioButton",
        "AXGroup", "AXMenuItem", "AXCheckBox", "AXMenuButton", "AXSwitch", "AXPopUpButton",
        "AXComboBox", "AXTextField", "AXTextArea", "AXLink", "AXImage",
        // Additional controls (#132)
        "AXSlider", "AXIncrementor", "AXDisclosureTriangle", "AXTab", "AXSegment"
    ]

    /// Actions to try for window elements, in order of preference.
    private static let preferredActions: [String] = [
        kAXPressAction as String, "AXSelect", "AXConfirm", "AXShowDefaultUI"
    ]

    /// Roles that require focus action instead of press.
    private static let rolesRequiringFocus: Set<String> = ["AXTextField"]

    /// Roles where setting `kAXSelectedAttribute` is a reliable primary interaction.
    private static let rolesSupportingSelectedAttribute: Set<String> = ["AXRow", "AXCell", "AXOutlineRow"]

    // MARK: - ActionExecutor Protocol

    /// Executes a Hint Mode target by performing the appropriate action on its AXUIElement.
    ///
    /// - Parameter target: The target to execute.
    /// - Returns: `.success(())` if execution succeeded, `.failure(HintExecutionError)` otherwise.
    func execute(_ target: HintTarget) -> Result<Void, HintExecutionError> {
        #if DEBUG
        logger.debug("execute: Starting execution for id=\(target.id) title='\(target.title)'")
        #endif

        target.element.performAction()
        return .success(())
    }

    // MARK: - Private Helpers

    /// Performs a mouse click at the center of the element's frame.
    ///
    /// This method tries direct attribute access first, then falls back to
    /// `AccessibilityHelper.getFrameWithFallback` if direct access fails.
    private func performMouseClick(on element: AXUIElement) -> Bool {
        var clickPoint: CGPoint?

        // Try direct attribute access first (returns Accessibility API coordinates: top-left origin)
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
           AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success {
            var position = CGPoint.zero
            var size = CGSize.zero

            // Note: kAXPositionAttribute and kAXSizeAttribute always return AXValue type
            // when the copy succeeds, so force cast is safe here.
            // swiftlint:disable force_cast
            AXValueGetValue(positionRef as! AXValue, .cgPoint, &position)
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
            // swiftlint:enable force_cast

            clickPoint = CGPoint(
                x: position.x + size.width / 2,
                y: position.y + size.height / 2
            )
        }

        // Fallback: use AccessibilityHelper.getFrameWithFallback
        // Note: getFrameWithFallback returns AppKit coordinates (bottom-left origin),
        // so we need to convert to Accessibility coordinates (top-left origin) for CGEvent.
        if clickPoint == nil, let frame = AccessibilityHelper.getFrameWithFallback(element) {
            if let screenHeight = NSScreen.main?.frame.height {
                // Convert from AppKit (bottom-left) to Accessibility (top-left) coordinates
                let accessibilityY = screenHeight - frame.origin.y - frame.height
                clickPoint = CGPoint(
                    x: frame.origin.x + frame.width / 2,
                    y: accessibilityY + frame.height / 2
                )
            }
        }

        guard let point = clickPoint else {
            #if DEBUG
            logger.warning("performMouseClick: Failed to get position/size")
            #endif
            return false
        }

        #if DEBUG
        logger.debug("performMouseClick: Clicking at \(point)")
        #endif

        guard let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            #if DEBUG
            logger.warning("performMouseClick: Failed to create mouse events")
            #endif
            return false
        }

        mouseDown.post(tap: .cghidEventTap)
        mouseUp.post(tap: .cghidEventTap)

        return true
    }
}
