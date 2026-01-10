//
//  HintTarget.swift
//  Portal
//
//  Created by Claude Code on 2025/12/31.
//

import ApplicationServices
import CoreGraphics

/// Represents an interactive UI element target for Hint Mode.
///
/// This is the minimal model Hint Mode needs:
/// - A stable display title for label selection
/// - An `AXUIElement` reference for execution
/// - Enabled state
/// - Cached frame (optional) for Electron apps where AXUIElement may become invalid
///
/// - Important: The `axElement` reference can become invalid if the source application
///   modifies its UI structure, quits, or crashes. The executor should handle failures.
///
/// ## Thread Safety
/// Marked as `@unchecked Sendable` because instances are created/executed on the main thread
/// via `WindowCrawler` and `AXUIElementPerformAction`.
struct HintTarget: Identifiable, @unchecked Sendable {
    /// Unique identifier using UUID to ensure uniqueness even for duplicate titles.
    let id: String = UUID().uuidString

    /// Display title of the target UI element.
    let title: String

    /// Reference to the accessibility element for performing actions.
    let axElement: AXUIElement

    /// Whether the target is currently enabled.
    let isEnabled: Bool

    /// Cached frame from crawl time. Used when AXUIElement becomes invalid (common in Electron apps).
    let cachedFrame: CGRect?

    init(title: String, axElement: AXUIElement, isEnabled: Bool, cachedFrame: CGRect? = nil) {
        self.title = title
        self.axElement = axElement
        self.isEnabled = isEnabled
        self.cachedFrame = cachedFrame
    }
}

// MARK: - Hashable conformance (excluding AXUIElement)

extension HintTarget: Hashable {
    static func == (lhs: HintTarget, rhs: HintTarget) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
