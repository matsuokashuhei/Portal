//
//  AccessibilityExecutor.swift
//  Portal
//
//  Created by Claude Code on 2026/01/01.
//  Renamed from HintActionExecutor on 2026/01/10.
//

import ApplicationServices

/// Service responsible for executing Hint Mode targets via Accessibility API.
///
/// It must run on the main thread as `AXUIElementPerformAction` requires it.
@MainActor
final class AccessibilityExecutor: ActionExecutor {
    /// Valid accessibility roles for window elements.
    private static let validRoles: Set<String> = [
        "AXRow", "AXCell", "AXOutlineRow", "AXStaticText", "AXButton", "AXRadioButton",
        "AXGroup", "AXMenuItem", "AXCheckBox", "AXMenuButton", "AXSwitch", "AXPopUpButton",
        "AXComboBox", "AXTextField"
    ]

    /// Actions to try for window elements, in order of preference.
    private static let preferredActions: [String] = [
        kAXPressAction as String, "AXSelect", "AXConfirm", "AXShowDefaultUI"
    ]

    /// Roles that require AXPress action (not kAXSelectedAttribute).
    private static let rolesRequiringPress: Set<String> = ["AXRadioButton", "AXButton", "AXMenuItem", "AXCheckBox", "AXMenuButton", "AXSwitch", "AXPopUpButton", "AXComboBox"]

    /// Roles that require focus action instead of press.
    private static let rolesRequiringFocus: Set<String> = ["AXTextField"]

    /// Roles where setting `kAXSelectedAttribute` is a reliable primary interaction.
    /// This is typically true for list/outline rows.
    private static let rolesSupportingSelectedAttribute: Set<String> = ["AXRow", "AXCell", "AXOutlineRow"]

    /// Executes a Hint Mode target by performing the appropriate action on its AXUIElement.
    ///
    /// - Parameter target: The target to execute.
    /// - Returns: `.success(())` if execution succeeded, `.failure(HintExecutionError)` otherwise.
    ///
    /// - Important: This method must be called on the main thread.
    func execute(_ target: HintTarget) -> Result<Void, HintExecutionError> {
        #if DEBUG
        print("[AccessibilityExecutor] execute: Starting execution for '\(target.title)'")
        #endif

        guard target.isEnabled else {
            #if DEBUG
            print("[AccessibilityExecutor] execute: Target is disabled")
            #endif
            return .failure(.targetDisabled)
        }

        // Validate that the axElement still references the expected item.
        // This prevents executing the wrong item when UI has changed.
        guard isElementValid(target.axElement, expectedTitle: target.title) else {
            #if DEBUG
            print("[AccessibilityExecutor] execute: Element validation failed")
            #endif
            return .failure(.elementInvalid)
        }

        // Get role to check if it requires AXPress
        var roleRef: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(target.axElement, kAXRoleAttribute as CFString, &roleRef)
        let role = (roleResult == .success) ? (roleRef as? String) : nil

        // For text fields, set focus instead of pressing
        let requiresFocus = role.map { Self.rolesRequiringFocus.contains($0) } ?? false
        if requiresFocus {
            #if DEBUG
            print("[AccessibilityExecutor] execute: Text field detected, setting focus")
            #endif
            let focusResult = AXUIElementSetAttributeValue(
                target.axElement,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue
            )
            if focusResult == .success {
                #if DEBUG
                print("[AccessibilityExecutor] execute: Focus set successfully")
                #endif
                return .success(())
            }
            #if DEBUG
            print("[AccessibilityExecutor] execute: Failed to set focus with result \(focusResult.rawValue)")
            #endif
            // Fall through to try other actions if focus fails
        }

        // Try setting AXSelected attribute first for list/outline rows.
        // Avoid doing this for container roles where a successful set may not imply a real action.
        if let r = role, Self.rolesSupportingSelectedAttribute.contains(r) {
            let selectResult = AXUIElementSetAttributeValue(
                target.axElement,
                kAXSelectedAttribute as CFString,
                kCFBooleanTrue
            )
            if selectResult == .success {
                return .success(())
            }
        }

        // For AXCheckBox and AXSwitch, use specialized toggle logic
        if let r = role, (r == "AXCheckBox" || r == "AXSwitch") {
            if executeCheckboxOrSwitch(target.axElement, role: r) {
                return .success(())
            }
            // Fall through to try other actions if toggle fails
        }

        // Try preferred actions
        let actions = Self.preferredActions

        // For window items, check if this is a container element (not AXButton)
        // If so, we should try child buttons instead of trusting AXPress success
        let isWindowContainer = !isButtonElement(target.axElement)

        for action in actions {
            let result = AXUIElementPerformAction(target.axElement, action as CFString)

            switch result {
            case .success:
                // For window containers, AXPress may return success without doing anything
                // Try child buttons as fallback
                if isWindowContainer && action == kAXPressAction as String {
                    if tryPressChildButtons(target.axElement) {
                        return .success(())
                    }
                    // Child button press failed, but main action "succeeded" - return success
                    // since we can't know if the original AXPress actually worked
                }
                return .success(())
            case .actionUnsupported:
                // Try next action
                continue
            case .invalidUIElement, .cannotComplete:
                return .failure(.elementInvalid)
            default:
                // Continue to next action on other failures
                continue
            }
        }

        // All actions failed - for window items, try child buttons as last resort
        if tryPressChildButtons(target.axElement) {
            return .success(())
        }

        return .failure(.actionFailed(-1))
    }

    /// Validates that an AXUIElement still points to the expected item.
    private func isElementValid(_ element: AXUIElement, expectedTitle: String) -> Bool {
        #if DEBUG
        print("[AccessibilityExecutor] isElementValid: Checking element for '\(expectedTitle)'")
        #endif

        // Verify role matches expected type first
        var roleRef: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        guard roleResult == .success, let role = roleRef as? String else {
            #if DEBUG
            print("[AccessibilityExecutor] isElementValid: Failed to get role (result: \(roleResult.rawValue)) for '\(expectedTitle)'")
            #endif
            return false
        }

        #if DEBUG
        print("[AccessibilityExecutor] isElementValid: Got role '\(role)' for '\(expectedTitle)'")
        #endif

        guard Self.validRoles.contains(role) else {
            #if DEBUG
            print("[AccessibilityExecutor] isElementValid: Role '\(role)' not in validRoles \(Self.validRoles)")
            #endif
            return false
        }

        // Verify title - check all possible title sources since NativeAppCrawler uses
        // title/description/value/help priority and we need to match any of them.
        var possibleTitles: [String] = []

        // Try direct title attribute
        var titleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
           let t = titleRef as? String, !t.isEmpty {
            possibleTitles.append(t)
        }

        // Try description
        var descRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef) == .success,
           let d = descRef as? String, !d.isEmpty {
            possibleTitles.append(d)
        }

        // Try value (used by some content labels)
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let v = valueRef as? String, !v.isEmpty {
            possibleTitles.append(v)
        }

        // Try placeholder value (used by text fields)
        var placeholderRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXPlaceholderValue" as CFString, &placeholderRef) == .success,
           let p = placeholderRef as? String, !p.isEmpty {
            possibleTitles.append(p)
        }

        // Also check child elements (for sidebar items like AXRow)
        if let childTitle = getTitleFromChildren(element), !childTitle.isEmpty {
            possibleTitles.append(childTitle)
        }

        // For AXCheckBox and AXSwitch, also check sibling elements for title
        if role == "AXCheckBox" || role == "AXSwitch" {
            if let siblingTitle = getTitleFromSiblings(element), !siblingTitle.isEmpty {
                possibleTitles.append(siblingTitle)
            }
        }

        guard possibleTitles.contains(expectedTitle) else {
            #if DEBUG
            print("[AccessibilityExecutor] isElementValid: Title '\(expectedTitle)' not found in possibleTitles: \(possibleTitles)")
            #endif
            return false
        }

        return true
    }

    /// Gets title from child elements (for sidebar items like AXRow).
    private func getTitleFromChildren(_ element: AXUIElement) -> String? {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }

        // Look for AXStaticText elements which contain the actual label
        for child in children {
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String, role == "AXStaticText" {
                // Try value first (most common for labels)
                var valueRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &valueRef) == .success,
                   let value = valueRef as? String, !value.isEmpty {
                    return value
                }
                // Fallback to title
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let title = titleRef as? String, !title.isEmpty {
                    return title
                }
            }

            // Check grandchildren
            var grandchildrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &grandchildrenRef) == .success,
               let grandchildren = grandchildrenRef as? [AXUIElement] {
                for grandchild in grandchildren {
                    var gcRoleRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(grandchild, kAXRoleAttribute as CFString, &gcRoleRef) == .success,
                       let gcRole = gcRoleRef as? String, gcRole == "AXStaticText" {
                        var valueRef: CFTypeRef?
                        if AXUIElementCopyAttributeValue(grandchild, kAXValueAttribute as CFString, &valueRef) == .success,
                           let value = valueRef as? String, !value.isEmpty {
                            return value
                        }
                        var titleRef: CFTypeRef?
                        if AXUIElementCopyAttributeValue(grandchild, kAXTitleAttribute as CFString, &titleRef) == .success,
                           let title = titleRef as? String, !title.isEmpty {
                            return title
                        }
                    }
                }
            }
        }

        return nil
    }

    /// Checks if an element is an AXButton.
    private func isButtonElement(_ element: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else {
            return false
        }
        return role == "AXButton"
    }

    /// Maximum depth for child button search to prevent stack overflow.
    private static let maxChildButtonSearchDepth = 5

    // MARK: - Checkbox/Switch Execution

    private func executeCheckboxOrSwitch(_ element: AXUIElement, role: String) -> Bool {
        #if DEBUG
        print("[AccessibilityExecutor] executeCheckboxOrSwitch: Starting for \(role)")
        #endif

        // Get current value before trying to toggle
        let valueBefore = getCheckboxValue(element)
        #if DEBUG
        print("[AccessibilityExecutor] executeCheckboxOrSwitch: Value before: \(valueBefore?.description ?? "nil")")
        #endif

        // Try AXPress first (works for most standard checkboxes)
        let pressResult = AXUIElementPerformAction(element, kAXPressAction as CFString)
        #if DEBUG
        print("[AccessibilityExecutor] executeCheckboxOrSwitch: AXPress result: \(pressResult.rawValue)")
        #endif

        if pressResult == .success {
            // Check if value actually changed
            let valueAfter = getCheckboxValue(element)
            #if DEBUG
            print("[AccessibilityExecutor] executeCheckboxOrSwitch: Value after AXPress: \(valueAfter?.description ?? "nil")")
            #endif

            // Handle different scenarios for value comparison
            if let before = valueBefore, let after = valueAfter {
                if before != after {
                    #if DEBUG
                    print("[AccessibilityExecutor] executeCheckboxOrSwitch: AXPress succeeded and value changed")
                    #endif
                    return true
                }
            } else if valueBefore == nil && valueAfter != nil {
                // Trust AXPress when we couldn't read before.
                #if DEBUG
                print("[AccessibilityExecutor] executeCheckboxOrSwitch: AXPress succeeded, trusting result (valueBefore was nil)")
                #endif
                return true
            }

            #if DEBUG
            print("[AccessibilityExecutor] executeCheckboxOrSwitch: AXPress returned success but value unchanged, trying direct toggle")
            #endif
        }

        // Try direct value toggle as fallback (required for some apps)
        if let currentValue = getCheckboxValue(element) {
            let expectedValue = !currentValue
            let newValue: CFBoolean = currentValue ? kCFBooleanFalse : kCFBooleanTrue
            let setResult = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newValue)
            #if DEBUG
            print("[AccessibilityExecutor] executeCheckboxOrSwitch: Direct toggle result: \(setResult.rawValue)")
            #endif

            if setResult == .success {
                let valueAfterToggle = getCheckboxValue(element)
                #if DEBUG
                print("[AccessibilityExecutor] executeCheckboxOrSwitch: Value after direct toggle: \(valueAfterToggle?.description ?? "nil")")
                #endif

                if let actualValue = valueAfterToggle {
                    if actualValue == expectedValue {
                        #if DEBUG
                        print("[AccessibilityExecutor] executeCheckboxOrSwitch: Direct toggle succeeded and value changed as expected")
                        #endif
                        return true
                    } else {
                        #if DEBUG
                        print("[AccessibilityExecutor] executeCheckboxOrSwitch: Direct toggle returned success but value did not change")
                        #endif
                    }
                } else {
                    // Cannot verify; trust success.
                    #if DEBUG
                    print("[AccessibilityExecutor] executeCheckboxOrSwitch: Direct toggle succeeded but value unavailable; treating as success")
                    #endif
                    return true
                }
            }
        }

        #if DEBUG
        print("[AccessibilityExecutor] executeCheckboxOrSwitch: Both approaches failed")
        #endif
        return false
    }

    private func getCheckboxValue(_ element: AXUIElement) -> Bool? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success else {
            return nil
        }

        if let intValue = valueRef as? Int {
            return intValue != 0
        }
        if let boolValue = valueRef as? Bool {
            return boolValue
        }
        if let numberValue = valueRef as? NSNumber {
            return numberValue.boolValue
        }
        return nil
    }

    private func getTitleFromSiblings(_ element: AXUIElement) -> String? {
        // Get the parent element
        var parentRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentRef) == .success else {
            return nil
        }
        // swiftlint:disable:next force_cast
        let parent = parentRef as! AXUIElement

        // Get sibling elements (children of parent)
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let siblings = childrenRef as? [AXUIElement] else {
            return nil
        }

        // Look for AXStaticText siblings that contain the label
        for sibling in siblings {
            if CFEqual(sibling, element) {
                continue
            }

            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(sibling, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String, role == "AXStaticText" {
                // Try value first (most common for labels)
                var valueRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(sibling, kAXValueAttribute as CFString, &valueRef) == .success,
                   let value = valueRef as? String, !value.isEmpty {
                    return value
                }
                // Fallback to title
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(sibling, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let title = titleRef as? String, !title.isEmpty {
                    return title
                }
            }
        }

        // Fallback: try the parent's description
        var descRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(parent, kAXDescriptionAttribute as CFString, &descRef) == .success,
           let desc = descRef as? String, !desc.isEmpty {
            return desc
        }

        return nil
    }

    private func tryPressChildButtons(_ element: AXUIElement, depth: Int = 0) -> Bool {
        guard depth < Self.maxChildButtonSearchDepth else {
            return false
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return false
        }

        for child in children {
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String, role == "AXButton" {
                let result = AXUIElementPerformAction(child, kAXPressAction as CFString)
                if result == .success {
                    return true
                }
            }

            if tryPressChildButtons(child, depth: depth + 1) {
                return true
            }
        }

        return false
    }
}

// MARK: - Backward Compatibility

/// Type alias for backward compatibility with existing code.
typealias HintActionExecutor = AccessibilityExecutor
