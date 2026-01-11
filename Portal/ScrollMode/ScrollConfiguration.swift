//
//  ScrollConfiguration.swift
//  Portal
//
//  Created by Claude Code on 2026/01/11.
//

import Foundation

/// Scroll key definitions used by Vimium-style keyboard scrolling.
///
/// Maps h/j/k/l keys to their Carbon key codes for use with CGEventTap.
/// This enum is nonisolated to allow access from CGEventTap callbacks.
nonisolated enum ScrollKey: String, CaseIterable, Sendable {
    case h, j, k, l

    /// Carbon key code for the key.
    var keyCode: Int64 {
        switch self {
        case .h: return 4   // H
        case .j: return 38  // J
        case .k: return 40  // K
        case .l: return 37  // L
        }
    }

    /// Creates a ScrollKey from a Carbon key code, if applicable.
    static func from(keyCode: Int64) -> ScrollKey? {
        allCases.first { $0.keyCode == keyCode }
    }
}

/// Scroll direction for scroll events.
enum ScrollDirection {
    case up, down, left, right
}

/// Configuration constants for scroll mode.
/// This enum is nonisolated to allow access from CGEventTap callbacks.
nonisolated enum ScrollConfiguration: Sendable {
    /// Scroll amount per key press (in pixels).
    ///
    /// A value of 60 provides Vimium-like scrolling that's
    /// responsive and noticeable per key press.
    static let scrollAmount: Int32 = 60

    /// Accessibility roles that indicate text input fields.
    ///
    /// When an element with one of these roles has focus,
    /// scroll keys are passed through to allow normal text input.
    static let textInputRoles: Set<String> = [
        "AXTextField",
        "AXTextArea",
        "AXComboBox",
        "AXSearchField"
    ]
}
