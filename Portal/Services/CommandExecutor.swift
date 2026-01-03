//
//  CommandExecutor.swift
//  Portal
//
//  Created by Claude Code on 2026/01/01.
//

import ApplicationServices

/// Service responsible for executing commands via Accessibility API.
///
/// This service can execute menu items and window UI elements.
/// It must run on the main thread as `AXUIElementPerformAction` requires it.
/// The `@MainActor` attribute ensures all method calls are dispatched to the main thread.
///
/// ## Testing
/// Unit testing this class is difficult because `AXUIElement` references cannot be mocked
/// without a real application context. The error handling paths are indirectly tested through
/// integration tests by executing commands against real applications. For isolated unit tests,
/// consider introducing a protocol abstraction if mock injection becomes necessary.
@MainActor
final class CommandExecutor {
    /// Valid accessibility roles for each command type.
    private static let validRoles: [CommandType: Set<String>] = [
        .menu: ["AXMenuItem"],
        .window: ["AXRow", "AXCell", "AXOutlineRow", "AXStaticText", "AXButton", "AXRadioButton", "AXGroup", "AXMenuItem", "AXCheckBox", "AXMenuButton", "AXSwitch", "AXPopUpButton", "AXComboBox", "AXTextField"]
    ]

    /// Actions to try for each command type, in order of preference.
    private static let preferredActions: [CommandType: [String]] = [
        .menu: [kAXPressAction as String],
        .window: [kAXPressAction as String, "AXSelect", "AXConfirm", "AXShowDefaultUI"]
    ]

    /// Roles that require AXPress action (not kAXSelectedAttribute).
    private static let rolesRequiringPress: Set<String> = ["AXRadioButton", "AXButton", "AXCheckBox", "AXMenuButton", "AXMenuItem", "AXSwitch", "AXPopUpButton", "AXComboBox"]

    /// Roles that require focus action instead of press.
    private static let rolesRequiringFocus: Set<String> = ["AXTextField"]

    /// Executes a command item by performing the appropriate action on its AXUIElement.
    ///
    /// - Parameter menuItem: The menu item to execute.
    /// - Returns: `.success(())` if execution succeeded, `.failure(CommandExecutionError)` otherwise.
    ///
    /// - Important: This method must be called on the main thread.
    func execute(_ menuItem: MenuItem) -> Result<Void, CommandExecutionError> {
        #if DEBUG
        print("[CommandExecutor] execute: Starting execution for '\(menuItem.title)' (type: \(menuItem.type))")
        #endif

        guard menuItem.isEnabled else {
            #if DEBUG
            print("[CommandExecutor] execute: Item is disabled")
            #endif
            return .failure(.itemDisabled)
        }

        // Validate that the axElement still references the expected item.
        // This prevents executing the wrong item when UI has changed.
        guard isElementValid(menuItem.axElement, expectedTitle: menuItem.title, type: menuItem.type) else {
            #if DEBUG
            print("[CommandExecutor] execute: Element validation failed")
            #endif
            return .failure(.elementInvalid)
        }

        // For window items (sidebar rows, outline rows, etc.), try setting AXSelected attribute first
        // This is more reliable than actions for list/outline rows
        // Exception: AXRadioButton and AXButton require AXPress action instead
        if menuItem.type == .window {
            // Get role to check if it requires AXPress
            var roleRef: CFTypeRef?
            let roleResult = AXUIElementCopyAttributeValue(menuItem.axElement, kAXRoleAttribute as CFString, &roleRef)
            let role = (roleResult == .success) ? (roleRef as? String) : nil

            // For AXMenuItem with submenu, use AXShowMenu instead of AXPress
            // AXPress doesn't work for menu items that have submenus
            let isSubmenuItem = role == "AXMenuItem" && hasSubmenu(menuItem.axElement)
            if isSubmenuItem {
                #if DEBUG
                print("[CommandExecutor] execute: AXMenuItem with submenu detected, trying AXShowMenu")
                #endif
                let showMenuResult = AXUIElementPerformAction(menuItem.axElement, "AXShowMenu" as CFString)
                if showMenuResult == .success {
                    #if DEBUG
                    print("[CommandExecutor] execute: AXShowMenu succeeded")
                    #endif
                    return .success(())
                }
                #if DEBUG
                print("[CommandExecutor] execute: AXShowMenu failed with result \(showMenuResult.rawValue), trying AXPress")
                #endif
                // Try AXPress for submenu items - some apps respond to this
                let pressResult = AXUIElementPerformAction(menuItem.axElement, kAXPressAction as CFString)
                if pressResult == .success {
                    #if DEBUG
                    print("[CommandExecutor] execute: AXPress succeeded for submenu item")
                    #endif
                    return .success(())
                }
                #if DEBUG
                print("[CommandExecutor] execute: AXPress failed with result \(pressResult.rawValue)")
                #endif
                // Fall through to other actions if both fail
            }

            // For text fields, set focus instead of pressing
            let requiresFocus = role.map { Self.rolesRequiringFocus.contains($0) } ?? false
            if requiresFocus {
                #if DEBUG
                print("[CommandExecutor] execute: Text field detected, setting focus")
                #endif
                let focusResult = AXUIElementSetAttributeValue(
                    menuItem.axElement,
                    kAXFocusedAttribute as CFString,
                    kCFBooleanTrue
                )
                if focusResult == .success {
                    #if DEBUG
                    print("[CommandExecutor] execute: Focus set successfully")
                    #endif
                    return .success(())
                }
                #if DEBUG
                print("[CommandExecutor] execute: Failed to set focus with result \(focusResult.rawValue)")
                #endif
                // Fall through to try other actions if focus fails
            }

            // Skip kAXSelectedAttribute for roles that require AXPress or for submenu items
            // (kAXSelectedAttribute just highlights the item without opening the submenu)
            let requiresPress = role.map { Self.rolesRequiringPress.contains($0) } ?? false
            if !requiresPress && !isSubmenuItem {
                let selectResult = AXUIElementSetAttributeValue(
                    menuItem.axElement,
                    kAXSelectedAttribute as CFString,
                    kCFBooleanTrue
                )
                if selectResult == .success {
                    return .success(())
                }
            }
        }

        // Try preferred actions for this command type
        let actions = Self.preferredActions[menuItem.type] ?? [kAXPressAction as String]

        // For window items, check if this is a container element (not AXButton)
        // If so, we should try child buttons instead of trusting AXPress success
        let isWindowContainer = menuItem.type == .window && !isButtonElement(menuItem.axElement)

        for action in actions {
            let result = AXUIElementPerformAction(menuItem.axElement, action as CFString)

            switch result {
            case .success:
                // For window containers, AXPress may return success without doing anything
                // Try child buttons as fallback
                if isWindowContainer && action == kAXPressAction as String {
                    if tryPressChildButtons(menuItem.axElement) {
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
        if menuItem.type == .window {
            if tryPressChildButtons(menuItem.axElement) {
                return .success(())
            }
        }

        return .failure(.actionFailed(-1))
    }

    /// Validates that an AXUIElement still points to the expected item.
    ///
    /// - Parameters:
    ///   - element: The AXUIElement to validate.
    ///   - expectedTitle: The title the element should have.
    ///   - type: The command type to validate against.
    /// - Returns: `true` if the element's title and role match expectations.
    ///
    /// ## Limitations
    /// This validation checks title and role, but not the full path. In theory,
    /// dynamic UIs could have items with the same title at different paths. In practice,
    /// this is rare because:
    /// 1. Items typically have unique titles within an application
    /// 2. Portal's typical use case is immediate execution after selection
    private func isElementValid(_ element: AXUIElement, expectedTitle: String, type: CommandType) -> Bool {
        #if DEBUG
        print("[CommandExecutor] isElementValid: Checking element for '\(expectedTitle)' (type: \(type))")
        #endif

        // Verify role matches expected type first
        var roleRef: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        guard roleResult == .success, let role = roleRef as? String else {
            #if DEBUG
            print("[CommandExecutor] isElementValid: Failed to get role (result: \(roleResult.rawValue)) for '\(expectedTitle)'")
            #endif
            return false
        }

        #if DEBUG
        print("[CommandExecutor] isElementValid: Got role '\(role)' for '\(expectedTitle)'")
        #endif

        guard let validRolesForType = Self.validRoles[type], validRolesForType.contains(role) else {
            #if DEBUG
            let expectedRoles = Self.validRoles[type] ?? []
            print("[CommandExecutor] isElementValid: Role '\(role)' not in validRoles \(expectedRoles) for type \(type)")
            #endif
            return false
        }

        // Verify title - check all possible title sources since WindowCrawler
        // uses title ?? description ?? value priority and we need to match any of them
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

        // Try value (used by content items like Apple Music "Now Playing")
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let v = valueRef as? String, !v.isEmpty {
            possibleTitles.append(v)
        }

        // Try placeholder value (used by text fields like "Find in Songs")
        var placeholderRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXPlaceholderValue" as CFString, &placeholderRef) == .success,
           let p = placeholderRef as? String, !p.isEmpty {
            possibleTitles.append(p)
        }

        // For window items, also check child elements
        if type == .window {
            if let childTitle = getTitleFromChildren(element), !childTitle.isEmpty {
                possibleTitles.append(childTitle)
            }
        }

        // Accept if expected title matches any of the possible titles
        guard possibleTitles.contains(expectedTitle) else {
            #if DEBUG
            print("[CommandExecutor] isElementValid: Title '\(expectedTitle)' not found in possibleTitles: \(possibleTitles)")
            #endif
            return false
        }

        return true
    }

    /// Gets title from child elements (for sidebar items like AXRow).
    /// Sidebar items often have their label in a child AXStaticText element.
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

    /// Checks if an AXMenuItem element has a submenu.
    ///
    /// Submenu items are detected by checking if the element has children,
    /// specifically looking for an AXMenu child element.
    ///
    /// - Parameter element: The AXUIElement to check.
    /// - Returns: `true` if the element has a submenu.
    private func hasSubmenu(_ element: AXUIElement) -> Bool {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return false
        }

        return children.contains { child in
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String {
                return role == "AXMenu"
            }
            return false
        }
    }

    /// Tries to press child button elements recursively.
    /// Some content items are containers (AXGroup) with the actual clickable button as a child.
    /// - Parameters:
    ///   - element: The parent element to search for child buttons.
    ///   - depth: Current recursion depth (default 0).
    /// - Returns: `true` if a child button was successfully pressed.
    private func tryPressChildButtons(_ element: AXUIElement, depth: Int = 0) -> Bool {
        // Limit recursion depth to prevent stack overflow
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

            // Recursively check grandchildren with incremented depth
            if tryPressChildButtons(child, depth: depth + 1) {
                return true
            }
        }

        return false
    }
}
