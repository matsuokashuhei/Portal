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
        logger.debug("execute: Starting execution for '\(target.title)'")
        #endif

        guard target.isEnabled else {
            #if DEBUG
            logger.debug("execute: Target is disabled")
            #endif
            return .failure(.targetDisabled)
        }

        // Validate that the axElement still references the expected item.
        let elementIsValid = isElementValid(target.axElement, expectedTitle: target.title, validRoles: Self.validRoles)
        if !elementIsValid {
            #if DEBUG
            logger.debug("execute: Element validation failed")
            #endif
            return .failure(.elementInvalid)
        }

        // Get role to determine execution strategy
        guard let role = getRole(target.axElement) else {
            #if DEBUG
            logger.warning("execute: Failed to get role")
            #endif
            return .failure(.elementInvalid)
        }

        // For text fields, set focus instead of pressing
        if Self.rolesRequiringFocus.contains(role) {
            #if DEBUG
            logger.debug("execute: Text field detected, setting focus")
            #endif
            if setFocus(target.axElement) {
                return .success(())
            }
            // Fall through to try other actions if focus fails
        }

        // For sliders, set focus to allow arrow key control (#132)
        if role == "AXSlider" {
            #if DEBUG
            logger.debug("execute: Slider detected, setting focus")
            #endif
            if setFocus(target.axElement) {
                return .success(())
            }
            // Fall through to try other actions if focus fails
        }

        // For incrementors, perform AXIncrement action (#132)
        if role == "AXIncrementor" {
            #if DEBUG
            logger.debug("execute: Incrementor detected, performing AXIncrement")
            #endif
            if performAction(target.axElement, action: "AXIncrement") {
                return .success(())
            }
            // Fall through to try other actions if increment fails
        }

        // Try setting AXSelected attribute first for list/outline rows.
        if Self.rolesSupportingSelectedAttribute.contains(role) {
            #if DEBUG
            logger.debug("execute: Trying AXSelected for role '\(role)'")
            #endif
            let selectResult = AXUIElementSetAttributeValue(
                target.axElement,
                kAXSelectedAttribute as CFString,
                kCFBooleanTrue
            )
            #if DEBUG
            logger.debug("execute: AXSelected result: \(selectResult.rawValue)")
            #endif

            // Try mouse click as more reliable fallback
            if performMouseClick(on: target.axElement) {
                return .success(())
            }

            // Try AXPress as final fallback for rows
            if performAction(target.axElement, action: kAXPressAction as String) {
                return .success(())
            }
        }

        // For AXCheckBox and AXSwitch, use specialized toggle logic
        if role == "AXCheckBox" || role == "AXSwitch" {
            if executeCheckboxOrSwitch(target.axElement, role: role) {
                return .success(())
            }
            // Fall through to try other actions if toggle fails
        }

        // Check if this is a window control button (close, minimize, zoom, fullscreen)
        // These buttons only respond to mouse click, not AXPress
        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(target.axElement, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subrole = subroleRef as? String {
            if AccessibilityHelper.windowControlSubroles.contains(subrole) {
                #if DEBUG
                logger.debug("execute: Window control button detected, using mouse click")
                #endif
                if performMouseClick(on: target.axElement) {
                    return .success(())
                }
                // Window control buttons don't support AXPress, return error immediately
                return .failure(.actionFailed(-1))
            }
        }

        // Try preferred actions
        let isWindowContainer = !isButtonElement(target.axElement)

        for action in Self.preferredActions {
            let result = AXUIElementPerformAction(target.axElement, action as CFString)
            #if DEBUG
            logger.debug("execute: Tried action '\(action)' result: \(result.rawValue)")
            #endif

            switch result {
            case .success:
                // For window containers, AXPress may return success without doing anything
                if isWindowContainer && action == kAXPressAction as String {
                    if tryPressChildButtons(target.axElement) {
                        return .success(())
                    }
                }
                return .success(())
            case .actionUnsupported:
                continue
            case .invalidUIElement, .cannotComplete:
                #if DEBUG
                logger.debug("execute: Action failed with \(result.rawValue), trying mouse click fallback")
                #endif
                // Try mouse click as fallback before failing
                if performMouseClick(on: target.axElement) {
                    return .success(())
                }
                return .failure(.elementInvalid)
            default:
                continue
            }
        }

        // All actions failed - try child buttons as last resort
        if tryPressChildButtons(target.axElement) {
            return .success(())
        }

        return .failure(.actionFailed(-1))
    }

    // MARK: - Private Helpers

    /// Sets focus on an element.
    private func setFocus(_ element: AXUIElement) -> Bool {
        let result = AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        #if DEBUG
        logger.debug("setFocus: Result \(result.rawValue)")
        #endif
        return result == .success
    }

    /// Performs an accessibility action on an element.
    private func performAction(_ element: AXUIElement, action: String) -> Bool {
        let result = AXUIElementPerformAction(element, action as CFString)
        #if DEBUG
        logger.debug("performAction '\(action)': Result \(result.rawValue)")
        #endif
        return result == .success
    }

    /// Executes checkbox or switch toggle with value verification.
    private func executeCheckboxOrSwitch(_ element: AXUIElement, role: String) -> Bool {
        #if DEBUG
        logger.debug("executeCheckboxOrSwitch: Starting for \(role)")
        #endif

        // Get current value before trying to toggle
        let valueBefore = getCheckboxValue(element)
        #if DEBUG
        logger.debug("executeCheckboxOrSwitch: Value before: \(valueBefore?.description ?? "nil")")
        #endif

        // Try AXPress first (works for most standard checkboxes)
        let pressResult = AXUIElementPerformAction(element, kAXPressAction as CFString)
        #if DEBUG
        logger.debug("executeCheckboxOrSwitch: AXPress result: \(pressResult.rawValue)")
        #endif

        if pressResult == .success {
            let valueAfter = getCheckboxValue(element)
            #if DEBUG
            logger.debug("executeCheckboxOrSwitch: Value after AXPress: \(valueAfter?.description ?? "nil")")
            #endif

            if let before = valueBefore, let after = valueAfter {
                if before != after {
                    return true
                }
            } else if valueBefore == nil && valueAfter != nil {
                return true
            }
        }

        // Try direct value toggle as fallback
        if let currentValue = getCheckboxValue(element) {
            let expectedValue = !currentValue
            let newValue: CFBoolean = currentValue ? kCFBooleanFalse : kCFBooleanTrue
            let setResult = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newValue)
            #if DEBUG
            logger.debug("executeCheckboxOrSwitch: Direct toggle result: \(setResult.rawValue)")
            #endif

            if setResult == .success {
                let valueAfterToggle = getCheckboxValue(element)
                if let actualValue = valueAfterToggle {
                    if actualValue == expectedValue {
                        return true
                    }
                } else {
                    return true
                }
            }
        }

        #if DEBUG
        logger.warning("executeCheckboxOrSwitch: Both approaches failed")
        #endif
        return false
    }

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
