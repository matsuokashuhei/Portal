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
/// - Warning: Mock items share a system-wide AXUIElement and should NOT be used
///   for execution tests. CommandExecutor will fail when attempting to execute
///   these items as they are not valid menu items.
enum MockMenuItemFactory {
    /// Creates an array of mock menu items.
    /// - Parameter count: Number of items to create.
    /// - Returns: Array of MenuItem with sequential titles.
    ///
    /// - Note: All items share the same dummy AXUIElement. These items are suitable
    ///   for UI layout and navigation testing, but not for command execution testing.
    static func createMockItems(count: Int) -> [MenuItem] {
        let dummyElement = AXUIElementCreateSystemWide()

        return (0..<count).map { index in
            MenuItem(
                title: "Menu Item \(index)",
                path: ["Test", "Menu Item \(index)"],
                keyboardShortcut: index < 10 ? "⌘\(index)" : nil,
                axElement: dummyElement,
                isEnabled: true
            )
        }
    }
}
