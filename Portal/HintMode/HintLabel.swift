//
//  HintLabel.swift
//  Portal
//
//  Created by Claude Code on 2026/01/03.
//

import CoreGraphics
import Foundation

/// Coordinate system used by the hint's frame.
///
/// Different UI frameworks use different coordinate origins, requiring
/// transformation when displaying hints in SwiftUI.
enum HintCoordinateSystem {
    /// Native macOS Accessibility API coordinates.
    ///
    /// - Origin: Top-left of the primary screen
    /// - Y-axis: Increases downward
    /// - Multi-screen: Coordinates are relative to the primary screen's top-left
    /// - Transformation: Requires Y-flip to convert to SwiftUI's bottom-left origin
    case native

    /// Electron/Chromium Accessibility coordinates.
    ///
    /// Electron apps (Slack, VS Code, Discord, etc.) return coordinates that are
    /// already compatible with NSScreen's coordinate system after crawling.
    /// - Origin: Effectively bottom-left of screen (post-crawl)
    /// - Y-axis: Increases upward
    /// - Transformation: No Y-flip needed
    case electron
}

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
    let frame: CGRect

    /// The target UI element associated with this hint.
    /// Contains the `axElement` reference for execution.
    let target: HintTarget

    /// The coordinate system used by this hint's frame.
    /// Determines how to transform coordinates for display.
    let coordinateSystem: HintCoordinateSystem

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
