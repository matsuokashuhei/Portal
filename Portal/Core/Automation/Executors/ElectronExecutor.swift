//
//  ElectronExecutor.swift
//  Portal
//
//  Created by Claude Code on 2026/01/12.
//

import ApplicationServices

/// Executor for Electron-based applications (Slack, VS Code, Discord, etc.).
///
/// Electron applications may have unstable AXUIElement references due to DOM updates.
/// This executor provides mouse click fallback using cached frames when accessibility
/// actions fail or elements become invalid.
///
/// ## Responsibilities
/// - Execute actions via Accessibility API with mouse click fallback
/// - Use cached frames when AXUIElement becomes invalid
/// - Handle Electron-specific behaviors
///
/// ## Thread Safety
/// All methods must be called on the main thread due to Accessibility API requirements.
@MainActor
final class ElectronExecutor: ActionExecutor {

    // MARK: - Role Definitions

    /// Valid accessibility roles for Electron applications.
    /// This includes both web-based roles and native chrome elements.
    static let validRoles: Set<String> = [
        // Web-based roles
        "AXLink", "AXButton", "AXTextField", "AXTextArea", "AXSearchField", "AXCheckBox",
        "AXRadioButton", "AXMenuItem", "AXMenuItemCheckbox", "AXMenuItemRadio",
        "AXTab", "AXStaticText", "AXRow", "AXPopUpButton", "AXMenuButton",
        "AXComboBox", "AXSwitch", "AXImage",
        // Native chrome roles (for window controls, menus)
        "AXGroup", "AXCell", "AXOutlineRow"
    ]

    /// Actions to try for elements, in order of preference.
    private static let preferredActions: [String] = [
        kAXPressAction as String, "AXSelect", "AXConfirm", "AXShowDefaultUI"
    ]

    /// Roles where setting `kAXSelectedAttribute` is a reliable primary interaction.
    private static let rolesSupportingSelectedAttribute: Set<String> = ["AXRow", "AXCell", "AXOutlineRow"]

    // MARK: - ActionExecutor Protocol

    /// Executes a Hint Mode target with fallback to mouse click using cached frame.
    ///
    /// - Parameter target: The target to execute.
    /// - Returns: `.success(())` if execution succeeded, `.failure(HintExecutionError)` otherwise.
    func execute(_ target: HintTarget, actionName: String?) -> Result<Void, HintExecutionError> {
        guard target.isEnabled else {
            return .failure(.targetDisabled)
        }

        // Electron apps may change element titles dynamically, so use relaxed matching
        // while still validating title/role to avoid executing the wrong element.
        let elementIsValid = isElementValid(
            target.axElement,
            expectedTitle: target.title,
            validRoles: Self.validRoles,
            validateTitle: true,
            titleMatchMode: .relaxed
        )

        if !elementIsValid {
            // For Electron apps, AXUIElement may become invalid but we have cachedFrame.
            // Try mouse click as fallback when we have a cached frame.
            if let cachedFrame = target.cachedFrame {
                if performMouseClickAtFrame(cachedFrame) {
                    return .success(())
                }
            }
            return .failure(.elementInvalid)
        }

        // Get role to determine execution strategy
        let role = getRole(target.axElement)

        // Try setting AXSelected attribute first for list/outline rows.
        if let role = role, Self.rolesSupportingSelectedAttribute.contains(role) {
            _ = AXUIElementSetAttributeValue(
                target.axElement,
                kAXSelectedAttribute as CFString,
                kCFBooleanTrue
            )

            // AXSelected may return success but not actually work in Electron apps
            // Try mouse click as more reliable approach
            if performMouseClick(on: target.axElement) {
                return .success(())
            }

            // Try AXPress as fallback
            if performAction(target.axElement, action: kAXPressAction as String) {
                return .success(())
            }
        }

        // If a specific action was selected, try it first.
        if let actionName {
            let result = AXUIElementPerformAction(target.axElement, actionName as CFString)
            switch result {
            case .success:
                return .success(())
            case .invalidUIElement, .cannotComplete:
                if let cachedFrame = target.cachedFrame {
                    if performMouseClickAtFrame(cachedFrame) {
                        return .success(())
                    }
                }
                return .failure(.elementInvalid)
            case .actionUnsupported:
                break
            default:
                break
            }
        }

        // Try preferred actions
        for action in Self.preferredActions {
            let result = AXUIElementPerformAction(target.axElement, action as CFString)

            switch result {
            case .success:
                return .success(())
            case .actionUnsupported:
                continue
            case .invalidUIElement, .cannotComplete:
                // Element became invalid - try cached frame fallback
                if let cachedFrame = target.cachedFrame {
                    if performMouseClickAtFrame(cachedFrame) {
                        return .success(())
                    }
                }
                return .failure(.elementInvalid)
            default:
                continue
            }
        }

        // All accessibility actions failed - try mouse click fallbacks

        // First try click on element if still valid
        if performMouseClick(on: target.axElement) {
            return .success(())
        }

        // Finally try cached frame
        if let cachedFrame = target.cachedFrame {
            if performMouseClickAtFrame(cachedFrame) {
                return .success(())
            }
        }

        // Try child buttons as last resort
        if tryPressChildButtons(target.axElement) {
            return .success(())
        }

        return .failure(.actionFailed(-1))
    }

    // MARK: - Private Helpers

    /// Performs an accessibility action on an element.
    private func performAction(_ element: AXUIElement, action: String) -> Bool {
        let result = AXUIElementPerformAction(element, action as CFString)
        return result == .success
    }

    /// Performs a mouse click at the center of the specified frame.
    /// This is used for Electron apps where AXUIElement may become invalid but we have cached frame.
    private func performMouseClickAtFrame(_ frame: CGRect) -> Bool {
        let clickPoint = CGPoint(
            x: frame.minX + frame.width / 2,
            y: frame.minY + frame.height / 2
        )

        guard let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: clickPoint, mouseButton: .left),
              let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: clickPoint, mouseButton: .left) else {
            return false
        }

        mouseDown.post(tap: .cghidEventTap)
        mouseUp.post(tap: .cghidEventTap)

        return true
    }

    /// Performs a mouse click at the center of the element's frame.
    private func performMouseClick(on element: AXUIElement) -> Bool {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success else {
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

        guard let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: clickPoint, mouseButton: .left),
              let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: clickPoint, mouseButton: .left) else {
            return false
        }

        mouseDown.post(tap: .cghidEventTap)
        mouseUp.post(tap: .cghidEventTap)

        return true
    }
}
