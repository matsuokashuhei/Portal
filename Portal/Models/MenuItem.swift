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
///
/// ## Thread Safety
/// This type is marked as `@unchecked Sendable` because:
/// - `MenuCrawler` is `@MainActor`, so all `MenuItem` instances are created on the main thread
/// - `CommandPaletteViewModel` is `@MainActor`, so all access to `MenuItem` occurs on the main thread
/// - The `AXUIElement` reference is only used for menu execution (Issue #50), which will also
///   occur on the main thread via `AXUIElementPerformAction`
/// - All other fields are immutable value types
///
/// If `MenuItem` is ever accessed from non-main threads, this assumption must be revisited.
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
        // Use null character as separator to avoid collisions with menu titles containing "/"
        self.id = path.joined(separator: "\0")
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
