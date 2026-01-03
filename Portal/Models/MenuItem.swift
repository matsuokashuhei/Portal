//
//  MenuItem.swift
//  Portal
//
//  Created by Claude Code on 2025/12/31.
//

import ApplicationServices

/// Type of command that can be executed.
///
/// Currently only supports window UI elements for hint mode navigation.
enum CommandType: String, Sendable {
    /// Window UI element (sidebar, toolbar, content area buttons, etc.)
    /// Includes AXSourceList, AXOutline, AXRow, AXButton, AXGroup, etc.
    /// Found in apps like Finder, Apple Music, Notes, System Settings.
    /// Crawled via `kAXMainWindowAttribute` using `WindowCrawler`.
    case window
}

/// Represents a command item from an application's UI.
///
/// This struct represents window UI elements used for hint mode navigation.
///
/// - Important: The `axElement` reference can become invalid if the source application
///   modifies its UI structure, quits, or crashes. The caller should handle `AXError`
///   appropriately when the element is no longer valid.
///
/// - Note: The `id` property uses a UUID generated at creation time to ensure uniqueness.
///   This prevents issues when multiple elements have the same title and path
///   (e.g., a "Blue" button and a "Blue" popup in System Settings Appearance).
///
/// ## Thread Safety
/// This type is marked as `@unchecked Sendable` because:
/// - `WindowCrawler` is `@MainActor`, so all `MenuItem` instances are created on the main thread
/// - The `AXUIElement` reference is only used for command execution, which will also
///   occur on the main thread via `AXUIElementPerformAction`
/// - All other fields are immutable value types
///
/// If `MenuItem` is ever accessed from non-main threads, this assumption must be revisited.
struct MenuItem: Identifiable, @unchecked Sendable {
    /// Unique identifier using UUID to ensure uniqueness.
    ///
    /// Previously used path-based ID which caused issues when multiple elements
    /// had the same title (e.g., "Blue" button and "Blue" popup in System Settings).
    let id: String = UUID().uuidString

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

    /// The type of UI element this item represents.
    let type: CommandType

    /// Formatted path string for display (e.g., "File → New → Document").
    var pathString: String {
        path.joined(separator: " → ")
    }

    /// Parent path string excluding the title (e.g., "File → New" for path ["File", "New", "Document"]).
    /// Returns nil if the path has only one element (no parent).
    var parentPathString: String? {
        guard path.count > 1 else { return nil }
        return path.dropLast().joined(separator: " → ")
    }

    init(
        title: String,
        path: [String],
        keyboardShortcut: String?,
        axElement: AXUIElement,
        isEnabled: Bool,
        type: CommandType = .window
    ) {
        self.title = title
        self.path = path
        self.keyboardShortcut = keyboardShortcut
        self.axElement = axElement
        self.isEnabled = isEnabled
        self.type = type
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
