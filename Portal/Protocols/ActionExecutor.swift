//
//  ActionExecutor.swift
//  Portal
//
//  Created by Claude Code on 2026/01/10.
//

import ApplicationServices

/// Protocol for executing actions on hint targets.
///
/// Implementations of this protocol are responsible for performing actions
/// on UI elements discovered by an `ElementCrawler`. Different implementations
/// can handle different types of targets (native macOS elements, web elements, etc.).
///
/// ## Thread Safety
/// All methods must be called on the main thread due to Accessibility API requirements.
@MainActor
protocol ActionExecutor {
    /// Executes an action on the specified hint target.
    ///
    /// - Parameter target: The target to execute an action on.
    /// - Returns: `.success(())` if the action was performed successfully,
    ///            `.failure(HintExecutionError)` otherwise.
    func execute(_ target: HintTarget) -> Result<Void, HintExecutionError>
}

// MARK: - Shared Helper Methods

/// Extension providing shared helper methods for all ActionExecutor implementations.
/// These methods contain common logic used by both NativeAppExecutor and ElectronExecutor.
extension ActionExecutor {

    /// Validates that an AXUIElement still points to the expected item.
    ///
    /// This prevents executing the wrong item when UI has changed.
    ///
    /// - Parameters:
    ///   - element: The AXUIElement to validate.
    ///   - expectedTitle: The title that was recorded when the target was discovered.
    ///   - validRoles: Set of valid accessibility roles for this executor.
    /// - Returns: `true` if the element is still valid and matches expectations.
    func isElementValid(_ element: AXUIElement, expectedTitle: String, validRoles: Set<String>) -> Bool {
        #if DEBUG
        print("[ActionExecutor] isElementValid: Checking element for '\(expectedTitle)'")
        #endif

        // Verify role matches expected type first
        var roleRef: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        guard roleResult == .success, let role = roleRef as? String else {
            #if DEBUG
            print("[ActionExecutor] isElementValid: Failed to get role (result: \(roleResult.rawValue)) for '\(expectedTitle)'")
            #endif
            return false
        }

        #if DEBUG
        print("[ActionExecutor] isElementValid: Got role '\(role)' for '\(expectedTitle)'")
        #endif

        guard validRoles.contains(role) else {
            #if DEBUG
            print("[ActionExecutor] isElementValid: Role '\(role)' not in validRoles \(validRoles)")
            #endif
            return false
        }

        // Verify title - check all possible title sources since crawlers use
        // title/description/value/help priority and we need to match any of them.
        var possibleTitles: [String] = []

        // Try direct title attribute
        var titleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
           let title = titleRef as? String, !title.isEmpty {
            possibleTitles.append(title)
        }

        // Try description
        var descRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef) == .success,
           let desc = descRef as? String, !desc.isEmpty {
            possibleTitles.append(desc)
        }

        // Try value (used by some content labels)
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let value = valueRef as? String, !value.isEmpty {
            possibleTitles.append(value)
        }

        // Try placeholder value (used by text fields)
        var placeholderRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXPlaceholderValue" as CFString, &placeholderRef) == .success,
           let placeholder = placeholderRef as? String, !placeholder.isEmpty {
            possibleTitles.append(placeholder)
        }

        // Try help attribute (used by some buttons like Xcode's toolbar buttons)
        var helpRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXHelpAttribute as CFString, &helpRef) == .success,
           let help = helpRef as? String, !help.isEmpty {
            possibleTitles.append(help)
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
            print("[ActionExecutor] isElementValid: Title '\(expectedTitle)' not found in possibleTitles: \(possibleTitles)")
            #endif
            return false
        }

        return true
    }

    /// Gets title from child elements (for sidebar items like AXRow).
    ///
    /// - Parameter element: The parent AXUIElement.
    /// - Returns: The title found in child elements, or `nil` if not found.
    func getTitleFromChildren(_ element: AXUIElement) -> String? {
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

    /// Gets title from sibling elements (for checkboxes/switches with separate labels).
    ///
    /// - Parameter element: The AXUIElement to check siblings of.
    /// - Returns: The title found in sibling elements, or `nil` if not found.
    func getTitleFromSiblings(_ element: AXUIElement) -> String? {
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

    /// Gets the boolean value of a checkbox or switch element.
    ///
    /// - Parameter element: The AXUIElement to get the value from.
    /// - Returns: The boolean value, or `nil` if the value cannot be read.
    func getCheckboxValue(_ element: AXUIElement) -> Bool? {
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

    /// Checks if an element is an AXButton.
    ///
    /// - Parameter element: The AXUIElement to check.
    /// - Returns: `true` if the element is an AXButton.
    func isButtonElement(_ element: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else {
            return false
        }
        return role == "AXButton"
    }

    /// Maximum depth for child button search to prevent stack overflow.
    private static var maxChildButtonSearchDepth: Int { 5 }

    /// Tries to press child buttons recursively.
    ///
    /// This is used as a fallback when the main element's AXPress action
    /// succeeds but doesn't actually do anything (common with container elements).
    ///
    /// - Parameters:
    ///   - element: The parent element to search for child buttons.
    ///   - depth: Current search depth (default 0).
    /// - Returns: `true` if a child button was successfully pressed.
    func tryPressChildButtons(_ element: AXUIElement, depth: Int = 0) -> Bool {
        guard depth < 5 else {  // maxChildButtonSearchDepth
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

    /// Gets the role of an AXUIElement.
    ///
    /// - Parameter element: The AXUIElement to get the role from.
    /// - Returns: The role string, or `nil` if the role cannot be read.
    func getRole(_ element: AXUIElement) -> String? {
        var roleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        guard result == .success, let role = roleRef as? String else {
            return nil
        }
        return role
    }
}
