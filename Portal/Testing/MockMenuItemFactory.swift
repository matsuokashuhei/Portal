//
//  MockMenuItemFactory.swift
//  Portal
//
//  Created by Claude Code on 2026/01/01.
//

import ApplicationServices

/// Factory for creating mock menu items for testing purposes.
/// This file is included in the app target to support UI testing with mock data.
///
/// ## Safety
/// Mock items are safe from accidental execution because:
/// 1. All items use `AXUIElementCreateSystemWide()` which is not a valid menu element
/// 2. `CommandExecutor.isElementValid()` checks title and role, which will fail validation
/// 3. The `[Mock]` prefix makes items visually identifiable as test data
///
/// - Warning: Do not use for execution tests. For testing execution, use real app menu items.
enum MockMenuItemFactory {
    /// Prefix added to all mock item titles to clearly identify them as test data.
    private static let mockPrefix = "[Mock] "

    /// Creates an array of mock menu items.
    /// - Parameters:
    ///   - count: Number of items to create.
    ///   - disabledIndices: Set of indices that should be disabled. Defaults to empty (all enabled).
    ///   - type: The command type for all items. Defaults to `.menu`.
    /// - Returns: Array of MenuItem with sequential titles prefixed with "[Mock] ".
    ///
    /// - Note: All items share the same dummy AXUIElement. These items are suitable
    ///   for UI layout and navigation testing, but not for command execution testing.
    ///   The "[Mock] " prefix makes it immediately obvious these are test items.
    static func createMockItems(
        count: Int,
        disabledIndices: Set<Int> = [],
        type: CommandType = .menu
    ) -> [MenuItem] {
        let dummyElement = AXUIElementCreateSystemWide()
        let menuName = menuNameForType(type)

        return (0..<count).map { index in
            let title = "\(mockPrefix)Item \(index)"
            return MenuItem(
                title: title,
                path: [menuName, title],
                keyboardShortcut: type == .menu && index < 10 ? "⌘\(index)" : nil,
                axElement: dummyElement,
                isEnabled: !disabledIndices.contains(index),
                type: type
            )
        }
    }

    /// Returns the parent menu/container name for the given command type.
    private static func menuNameForType(_ type: CommandType) -> String {
        switch type {
        case .menu:
            return "Mock Menu"
        case .sidebar:
            return "Mock Sidebar"
        case .button:
            return "Mock Window"
        }
    }
}
