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
    /// Prefix added to all mock item titles to clearly identify them as test data.
    private static let mockPrefix = "[Mock] "

    /// Creates an array of mock menu items.
    /// - Parameter count: Number of items to create.
    /// - Returns: Array of MenuItem with sequential titles prefixed with "[Mock] ".
    ///
    /// - Note: All items share the same dummy AXUIElement. These items are suitable
    ///   for UI layout and navigation testing, but not for command execution testing.
    ///   The "[Mock] " prefix makes it immediately obvious these are test items.
    static func createMockItems(count: Int) -> [MenuItem] {
        let dummyElement = AXUIElementCreateSystemWide()

        return (0..<count).map { index in
            let title = "\(mockPrefix)Item \(index)"
            return MenuItem(
                title: title,
                path: ["Mock Menu", title],
                keyboardShortcut: index < 10 ? "⌘\(index)" : nil,
                axElement: dummyElement,
                isEnabled: true
            )
        }
    }
}
