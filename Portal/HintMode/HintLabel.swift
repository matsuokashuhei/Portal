//
//  HintLabel.swift
//  Portal
//
//  Created by Claude Code on 2026/01/03.
//

import CoreGraphics
import Foundation

/// Represents a hint label displayed on the overlay for keyboard navigation.
///
/// Each `HintLabel` corresponds to an interactive UI element in the target application.
/// The user types the label characters to select and execute the corresponding element.
struct HintLabel: Identifiable {
    /// Unique identifier (same as `label`).
    var id: String { label }

    /// Display label for keyboard navigation (e.g., "A", "AB", "ZZ").
    let label: String

    /// Screen coordinates where the label should be displayed.
    /// This is in AppKit coordinate system (origin at bottom-left).
    let frame: CGRect

    /// The menu item associated with this hint.
    /// Contains the `axElement` reference for command execution.
    let menuItem: MenuItem

    /// Center point of the frame for label positioning.
    var centerPoint: CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }

    /// Top-left corner position for label display.
    /// Labels are typically displayed at the top-left of the element.
    var displayPosition: CGPoint {
        CGPoint(x: frame.minX, y: frame.maxY)
    }
}

// MARK: - Equatable

extension HintLabel: Equatable {
    static func == (lhs: HintLabel, rhs: HintLabel) -> Bool {
        lhs.label == rhs.label
    }
}

// MARK: - Hashable

extension HintLabel: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(label)
    }
}
