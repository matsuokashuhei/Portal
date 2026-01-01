//
//  MockMenuItemFactory.swift
//  Portal
//
//  Created by Claude Code on 2026/01/01.
//

import ApplicationServices

/// Factory for creating mock menu items for testing purposes.
/// This file is included in the app target to support UI testing with mock data.
enum MockMenuItemFactory {
    /// Creates an array of mock menu items.
    /// - Parameter count: Number of items to create.
    /// - Returns: Array of MenuItem with sequential titles.
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
