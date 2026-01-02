//
//  CommandExecutor.swift
//  Portal
//
//  Created by Claude Code on 2026/01/01.
//

import ApplicationServices

/// Service responsible for executing commands via Accessibility API.
///
/// This service can execute menu items, sidebar navigation items, and window buttons.
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
        .sidebar: ["AXRow", "AXCell", "AXOutlineRow", "AXStaticText"],
        .button: ["AXButton", "AXCheckBox"]
    ]

    /// Actions to try for each command type, in order of preference.
    private static let preferredActions: [CommandType: [String]] = [
        .menu: [kAXPressAction as String],
        .sidebar: [kAXPressAction as String, "AXSelect", "AXConfirm"],
        .button: [kAXPressAction as String]
    ]

    /// Executes a command item by performing the appropriate action on its AXUIElement.
    ///
    /// - Parameter menuItem: The menu item to execute.
    /// - Returns: `.success(())` if execution succeeded, `.failure(CommandExecutionError)` otherwise.
    ///
    /// - Important: This method must be called on the main thread.
    func execute(_ menuItem: MenuItem) -> Result<Void, CommandExecutionError> {
        guard menuItem.isEnabled else {
            return .failure(.itemDisabled)
        }

        // Validate that the axElement still references the expected item.
        // This prevents executing the wrong item when UI has changed.
        guard isElementValid(menuItem.axElement, expectedTitle: menuItem.title, type: menuItem.type) else {
            return .failure(.elementInvalid)
        }

        // Try preferred actions for this command type
        let actions = Self.preferredActions[menuItem.type] ?? [kAXPressAction as String]

        for action in actions {
            let result = AXUIElementPerformAction(menuItem.axElement, action as CFString)

            switch result {
            case .success:
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

        // All actions failed
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
        // Verify title (or description for some sidebar items)
        var titleRef: CFTypeRef?
        var title: String?

        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success {
            title = titleRef as? String
        }

        // Some sidebar items use description instead of title
        if title == nil || title?.isEmpty == true {
            var descRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef) == .success {
                title = descRef as? String
            }
        }

        guard let actualTitle = title, actualTitle == expectedTitle else {
            return false
        }

        // Verify role matches expected type
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else {
            return false
        }

        guard let validRoles = Self.validRoles[type], validRoles.contains(role) else {
            return false
        }

        return true
    }
}
