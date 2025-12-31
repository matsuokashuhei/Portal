//
//  MenuItem.swift
//  Portal
//
//  Created by Claude Code on 2025/12/31.
//

import ApplicationServices

/// Represents a menu item from an application's menu bar.
///
/// - Important: The `axElement` reference can become invalid if the source application
///   modifies its menu structure, quits, or crashes. When executing menu actions (Issue #50),
///   the caller should handle `AXError` appropriately when the element is no longer valid.
///   The short cache duration (0.5s) in `MenuCrawler` helps mitigate stale references.
struct MenuItem: Identifiable, @unchecked Sendable {
    /// Unique identifier based on menu path.
    let id: String

    /// Display title of the menu item.
    let title: String

    /// Hierarchical path to the menu item (e.g., ["File", "New", "Document"]).
    let path: [String]

    /// Keyboard shortcut if available (e.g., "⌘N").
    let keyboardShortcut: String?

    /// Reference to the accessibility element for performing actions.
    /// - Note: This reference may become invalid if the target app modifies its menus.
    let axElement: AXUIElement

    /// Whether the menu item is currently enabled.
    let isEnabled: Bool

    /// Formatted path string for display (e.g., "File → New → Document").
    var pathString: String {
        path.joined(separator: " → ")
    }

    init(
        title: String,
        path: [String],
        keyboardShortcut: String?,
        axElement: AXUIElement,
        isEnabled: Bool
    ) {
        self.id = path.joined(separator: "/")
        self.title = title
        self.path = path
        self.keyboardShortcut = keyboardShortcut
        self.axElement = axElement
        self.isEnabled = isEnabled
    }
}

// MARK: - Hashable conformance (excluding AXUIElement)

extension MenuItem: Hashable {
    static func == (lhs: MenuItem, rhs: MenuItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
