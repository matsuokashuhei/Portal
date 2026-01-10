//
//  HintExecutionError.swift
//  Portal
//
//  Created by Claude Code on 2026/01/01.
//

import Foundation

/// Error types for Hint Mode execution operations.
enum HintExecutionError: Error, LocalizedError {
    /// The accessibility element is no longer valid (app quit, UI changed).
    case elementInvalid
    /// The target is disabled and cannot be executed.
    case targetDisabled
    /// AXUIElementPerformAction failed with the given AXError code.
    case actionFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .elementInvalid:
            return "Target element is no longer available. Activate Hint Mode again and retry."
        case .targetDisabled:
            return "This item is currently disabled in the target app."
        case .actionFailed(let code):
            return "Execution failed (code: \(code)). Activate Hint Mode again and retry."
        }
    }
}
