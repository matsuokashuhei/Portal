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
            // Menu cache refreshes automatically on each panel open (0.5s cache duration)
            return "Menu item unavailable. Close and reopen the palette to refresh."
        case .itemDisabled:
            return "This menu item is disabled. Check if the required conditions are met in the app."
        case .actionFailed(let code):
            return "Execution failed (code: \(code)). Close and reopen the palette to refresh."
        }
    }
}
