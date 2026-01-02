//
//  MenuItemTests.swift
//  PortalTests
//
//  Created by Claude Code on 2025/12/31.
//

import ApplicationServices
import Testing
@testable import Portal

struct MenuItemTests {

    // Helper to create a dummy AXUIElement for testing
    private func createDummyElement() -> AXUIElement {
        AXUIElementCreateSystemWide()
    }

    @Test
    func testIdGenerationFromPath() {
        let element = createDummyElement()
        let item = MenuItem(
            title: "New",
            path: ["File", "New"],
            keyboardShortcut: "⌘N",
            axElement: element,
            isEnabled: true
        )

        // ID should be type + null + path joined with null character
        #expect(item.id == "menu\0File\0New")
    }

    @Test
    func testIdUniquenessWithDifferentPaths() {
        let element = createDummyElement()

        let item1 = MenuItem(
            title: "New",
            path: ["File", "New"],
            keyboardShortcut: nil,
            axElement: element,
            isEnabled: true
        )

        let item2 = MenuItem(
            title: "New",
            path: ["Edit", "New"],
            keyboardShortcut: nil,
            axElement: element,
            isEnabled: true
        )

        #expect(item1.id != item2.id)
    }

    @Test
    func testIdWithSlashInTitle() {
        let element = createDummyElement()

        // Test that "/" in title doesn't cause ID collision
        let item1 = MenuItem(
            title: "Open/Close",
            path: ["File", "Open/Close"],
            keyboardShortcut: nil,
            axElement: element,
            isEnabled: true
        )

        let item2 = MenuItem(
            title: "Close",
            path: ["File", "Open", "Close"],
            keyboardShortcut: nil,
            axElement: element,
            isEnabled: true
        )

        // These should have different IDs because we use null separator
        #expect(item1.id != item2.id)
    }

    @Test
    func testHashableConformance() {
        let element = createDummyElement()

        let item1 = MenuItem(
            title: "New",
            path: ["File", "New"],
            keyboardShortcut: "⌘N",
            axElement: element,
            isEnabled: true
        )

        let item2 = MenuItem(
            title: "New",
            path: ["File", "New"],
            keyboardShortcut: "⌘N",
            axElement: element,
            isEnabled: true
        )

        // Same ID should produce equal items and same hash
        #expect(item1 == item2)
        #expect(item1.hashValue == item2.hashValue)
    }

    @Test
    func testHashableWithDifferentIds() {
        let element = createDummyElement()

        let item1 = MenuItem(
            title: "New",
            path: ["File", "New"],
            keyboardShortcut: nil,
            axElement: element,
            isEnabled: true
        )

        let item2 = MenuItem(
            title: "Open",
            path: ["File", "Open"],
            keyboardShortcut: nil,
            axElement: element,
            isEnabled: true
        )

        #expect(item1 != item2)
    }

    @Test
    func testPathStringFormatting() {
        let element = createDummyElement()
        let item = MenuItem(
            title: "Document",
            path: ["File", "New", "Document"],
            keyboardShortcut: nil,
            axElement: element,
            isEnabled: true
        )

        #expect(item.pathString == "File → New → Document")
    }

    @Test
    func testPathStringWithSingleElement() {
        let element = createDummyElement()
        let item = MenuItem(
            title: "About",
            path: ["About"],
            keyboardShortcut: nil,
            axElement: element,
            isEnabled: true
        )

        #expect(item.pathString == "About")
    }

    @Test
    func testPathStringWithEmptyPath() {
        let element = createDummyElement()
        let item = MenuItem(
            title: "",
            path: [],
            keyboardShortcut: nil,
            axElement: element,
            isEnabled: true
        )

        #expect(item.pathString == "")
        // ID includes type prefix even with empty path
        #expect(item.id == "menu\0")
    }

    @Test
    func testSetContainment() {
        let element = createDummyElement()

        let item1 = MenuItem(
            title: "New",
            path: ["File", "New"],
            keyboardShortcut: nil,
            axElement: element,
            isEnabled: true
        )

        let item2 = MenuItem(
            title: "New",
            path: ["File", "New"],
            keyboardShortcut: nil,
            axElement: element,
            isEnabled: true
        )

        var set: Set<MenuItem> = [item1]
        set.insert(item2)

        // Same ID means same item, so set should have only 1 element
        #expect(set.count == 1)
    }

    // MARK: - CommandType Tests

    @Test
    func testDefaultTypeIsMenu() {
        let element = createDummyElement()
        let item = MenuItem(
            title: "New",
            path: ["File", "New"],
            keyboardShortcut: nil,
            axElement: element,
            isEnabled: true
        )

        #expect(item.type == .menu)
    }

    @Test
    func testExplicitTypeAssignment() {
        let element = createDummyElement()

        let sidebarItem = MenuItem(
            title: "Library",
            path: ["Music", "Library"],
            keyboardShortcut: nil,
            axElement: element,
            isEnabled: true,
            type: .sidebar
        )

        let buttonItem = MenuItem(
            title: "OK",
            path: ["Dialog", "OK"],
            keyboardShortcut: nil,
            axElement: element,
            isEnabled: true,
            type: .button
        )

        #expect(sidebarItem.type == .sidebar)
        #expect(buttonItem.type == .button)
    }

    @Test
    func testIdIncludesType() {
        let element = createDummyElement()

        let menuItem = MenuItem(
            title: "Library",
            path: ["App", "Library"],
            keyboardShortcut: nil,
            axElement: element,
            isEnabled: true,
            type: .menu
        )

        let sidebarItem = MenuItem(
            title: "Library",
            path: ["App", "Library"],
            keyboardShortcut: nil,
            axElement: element,
            isEnabled: true,
            type: .sidebar
        )

        // Same path but different types should produce different IDs
        #expect(menuItem.id != sidebarItem.id)
        #expect(menuItem.id.hasPrefix("menu\0"))
        #expect(sidebarItem.id.hasPrefix("sidebar\0"))
    }

    @Test
    func testDifferentTypesAreNotEqual() {
        let element = createDummyElement()

        let menuItem = MenuItem(
            title: "Library",
            path: ["App", "Library"],
            keyboardShortcut: nil,
            axElement: element,
            isEnabled: true,
            type: .menu
        )

        let sidebarItem = MenuItem(
            title: "Library",
            path: ["App", "Library"],
            keyboardShortcut: nil,
            axElement: element,
            isEnabled: true,
            type: .sidebar
        )

        #expect(menuItem != sidebarItem)
    }

    @Test
    func testSetContainmentWithDifferentTypes() {
        let element = createDummyElement()

        let menuItem = MenuItem(
            title: "Library",
            path: ["App", "Library"],
            keyboardShortcut: nil,
            axElement: element,
            isEnabled: true,
            type: .menu
        )

        let sidebarItem = MenuItem(
            title: "Library",
            path: ["App", "Library"],
            keyboardShortcut: nil,
            axElement: element,
            isEnabled: true,
            type: .sidebar
        )

        var set: Set<MenuItem> = [menuItem]
        set.insert(sidebarItem)

        // Different types means different items, so set should have 2 elements
        #expect(set.count == 2)
    }

    @Test
    func testParentPathString() {
        let element = createDummyElement()

        let item = MenuItem(
            title: "Document",
            path: ["File", "New", "Document"],
            keyboardShortcut: nil,
            axElement: element,
            isEnabled: true
        )

        #expect(item.parentPathString == "File → New")
    }

    @Test
    func testParentPathStringWithSingleElement() {
        let element = createDummyElement()

        let item = MenuItem(
            title: "About",
            path: ["About"],
            keyboardShortcut: nil,
            axElement: element,
            isEnabled: true
        )

        #expect(item.parentPathString == nil)
    }
}
