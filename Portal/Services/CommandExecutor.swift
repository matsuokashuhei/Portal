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
}
