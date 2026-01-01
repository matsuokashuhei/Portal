//
//  CommandExecutionError.swift
//  Portal
//
//  Created by Claude Code on 2026/01/01.
//

import Foundation

/// Error types for command execution operations.
enum CommandExecutionError: Error, LocalizedError {
    /// The accessibility element is no longer valid (app quit, menu changed).
    case elementInvalid
    /// The menu item is disabled and cannot be executed.
    case itemDisabled
    /// AXUIElementPerformAction failed with the given AXError code.
    case actionFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .elementInvalid:
            return "The menu item is no longer available. The target app may have changed its menus."
        case .itemDisabled:
            return "This menu item is currently disabled."
        case .actionFailed(let code):
            return "Failed to execute menu action (error code: \(code))."
        }
    }
}
