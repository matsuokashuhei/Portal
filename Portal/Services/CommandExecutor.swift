//
//  CommandExecutor.swift
//  Portal
//
//  Created by Claude Code on 2026/01/01.
//

import ApplicationServices

/// Service responsible for executing menu commands via Accessibility API.
///
/// This service must run on the main thread as `AXUIElementPerformAction` requires it.
/// The `@MainActor` attribute ensures all method calls are dispatched to the main thread.
///
/// ## Testing
/// Unit testing this class is difficult because `AXUIElement` references cannot be mocked
/// without a real application context. The error handling paths are indirectly tested through
/// integration tests by executing commands against real applications. For isolated unit tests,
/// consider introducing a protocol abstraction if mock injection becomes necessary.
@MainActor
final class CommandExecutor {
    /// Executes a menu item by performing the press action on its AXUIElement.
    ///
    /// - Parameter menuItem: The menu item to execute.
    /// - Returns: `.success(())` if execution succeeded, `.failure(CommandExecutionError)` otherwise.
    ///
    /// - Important: This method must be called on the main thread.
    func execute(_ menuItem: MenuItem) -> Result<Void, CommandExecutionError> {
        guard menuItem.isEnabled else {
            return .failure(.itemDisabled)
        }

        // Validate that the axElement still references the expected menu item.
        // This prevents executing the wrong menu item when menus have changed
        // (especially important for Finder whose menus change dynamically).
        guard isElementValid(menuItem.axElement, expectedTitle: menuItem.title) else {
            return .failure(.elementInvalid)
        }

        let result = AXUIElementPerformAction(menuItem.axElement, kAXPressAction as CFString)

        switch result {
        case .success:
            return .success(())
        case .invalidUIElement, .cannotComplete:
            return .failure(.elementInvalid)
        default:
            return .failure(.actionFailed(result.rawValue))
        }
    }

    /// Validates that an AXUIElement still points to the expected menu item.
    ///
    /// - Parameters:
    ///   - element: The AXUIElement to validate.
    ///   - expectedTitle: The title the element should have.
    /// - Returns: `true` if the element's current title matches the expected title.
    private func isElementValid(_ element: AXUIElement, expectedTitle: String) -> Bool {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String else {
            return false
        }
        return title == expectedTitle
    }
}
