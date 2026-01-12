//
//  NativeAppExecutor.swift
//  Portal
//
//  Created by Claude Code on 2026/01/12.
//

import ApplicationServices

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
        "AXSlider", "AXIncrementor", "AXDisclosureTriangle", "AXTab", "AXSegment",
        // Window control buttons (#136)
        "AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton"
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
        print("[NativeAppExecutor] execute: Starting execution for '\(target.title)'")
        #endif

        guard target.isEnabled else {
            #if DEBUG
            print("[NativeAppExecutor] execute: Target is disabled")
            #endif
            return .failure(.targetDisabled)
        }

        // Validate that the axElement still references the expected item.
        let elementIsValid = isElementValid(target.axElement, expectedTitle: target.title, validRoles: Self.validRoles)
        if !elementIsValid {
            #if DEBUG
            print("[NativeAppExecutor] execute: Element validation failed")
            #endif
            return .failure(.elementInvalid)
        }

        // Get role to determine execution strategy
        guard let role = getRole(target.axElement) else {
            #if DEBUG
            print("[NativeAppExecutor] execute: Failed to get role")
            #endif
            return .failure(.elementInvalid)
        }

        // For text fields, set focus instead of pressing
        if Self.rolesRequiringFocus.contains(role) {
            #if DEBUG
            print("[NativeAppExecutor] execute: Text field detected, setting focus")
            #endif
            if setFocus(target.axElement) {
                return .success(())
            }
            // Fall through to try other actions if focus fails
        }

        // For sliders, set focus to allow arrow key control (#132)
        if role == "AXSlider" {
            #if DEBUG
            print("[NativeAppExecutor] execute: Slider detected, setting focus")
            #endif
            if setFocus(target.axElement) {
                return .success(())
            }
            // Fall through to try other actions if focus fails
        }

        // For incrementors, perform AXIncrement action (#132)
        if role == "AXIncrementor" {
            #if DEBUG
            print("[NativeAppExecutor] execute: Incrementor detected, performing AXIncrement")
            #endif
            if performAction(target.axElement, action: "AXIncrement") {
                return .success(())
            }
            // Fall through to try other actions if increment fails
        }

        // Try setting AXSelected attribute first for list/outline rows.
        if Self.rolesSupportingSelectedAttribute.contains(role) {
            #if DEBUG
            print("[NativeAppExecutor] execute: Trying AXSelected for role '\(role)'")
            #endif
            let selectResult = AXUIElementSetAttributeValue(
                target.axElement,
                kAXSelectedAttribute as CFString,
                kCFBooleanTrue
            )
            #if DEBUG
            print("[NativeAppExecutor] execute: AXSelected result: \(selectResult.rawValue)")
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

        // Try preferred actions
        let isWindowContainer = !isButtonElement(target.axElement)

        for action in Self.preferredActions {
            let result = AXUIElementPerformAction(target.axElement, action as CFString)

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
        print("[NativeAppExecutor] setFocus: Result \(result.rawValue)")
        #endif
        return result == .success
    }

    /// Performs an accessibility action on an element.
    private func performAction(_ element: AXUIElement, action: String) -> Bool {
        let result = AXUIElementPerformAction(element, action as CFString)
        #if DEBUG
        print("[NativeAppExecutor] performAction '\(action)': Result \(result.rawValue)")
        #endif
        return result == .success
    }

    /// Executes checkbox or switch toggle with value verification.
    private func executeCheckboxOrSwitch(_ element: AXUIElement, role: String) -> Bool {
        #if DEBUG
        print("[NativeAppExecutor] executeCheckboxOrSwitch: Starting for \(role)")
        #endif

        // Get current value before trying to toggle
        let valueBefore = getCheckboxValue(element)
        #if DEBUG
        print("[NativeAppExecutor] executeCheckboxOrSwitch: Value before: \(valueBefore?.description ?? "nil")")
        #endif

        // Try AXPress first (works for most standard checkboxes)
        let pressResult = AXUIElementPerformAction(element, kAXPressAction as CFString)
        #if DEBUG
        print("[NativeAppExecutor] executeCheckboxOrSwitch: AXPress result: \(pressResult.rawValue)")
        #endif

        if pressResult == .success {
            let valueAfter = getCheckboxValue(element)
            #if DEBUG
            print("[NativeAppExecutor] executeCheckboxOrSwitch: Value after AXPress: \(valueAfter?.description ?? "nil")")
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
            print("[NativeAppExecutor] executeCheckboxOrSwitch: Direct toggle result: \(setResult.rawValue)")
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
        print("[NativeAppExecutor] executeCheckboxOrSwitch: Both approaches failed")
        #endif
        return false
    }

    /// Performs a mouse click at the center of the element's frame.
    private func performMouseClick(on element: AXUIElement) -> Bool {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success else {
            #if DEBUG
            print("[NativeAppExecutor] performMouseClick: Failed to get position/size")
            #endif
            return false
        }

        var position = CGPoint.zero
        var size = CGSize.zero

        // Note: kAXPositionAttribute and kAXSizeAttribute always return AXValue type
        // when the copy succeeds, so force cast is safe here.
        // swiftlint:disable force_cast
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        // swiftlint:enable force_cast

        let clickPoint = CGPoint(
            x: position.x + size.width / 2,
            y: position.y + size.height / 2
        )

        #if DEBUG
        print("[NativeAppExecutor] performMouseClick: Clicking at \(clickPoint)")
        #endif

        guard let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: clickPoint, mouseButton: .left),
              let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: clickPoint, mouseButton: .left) else {
            #if DEBUG
            print("[NativeAppExecutor] performMouseClick: Failed to create mouse events")
            #endif
            return false
        }

        mouseDown.post(tap: .cghidEventTap)
        mouseUp.post(tap: .cghidEventTap)

        return true
    }
}
