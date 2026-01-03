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
    func testIdIsUUID() {
        let element = createDummyElement()
        let item = MenuItem(
            title: "New",
            path: ["File", "New"],
            keyboardShortcut: "⌘N",
            axElement: element,
            isEnabled: true
        )

        // ID should be a valid UUID string (36 characters with hyphens)
        #expect(item.id.count == 36)
        #expect(UUID(uuidString: item.id) != nil)
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

        // Each MenuItem has a unique UUID, so they are NOT equal even with same path
        // This is intentional to support items with the same title (e.g., "Blue" button and "Blue" popup)
        #expect(item1 != item2)
        #expect(item1.hashValue != item2.hashValue)
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
        // ID is a UUID regardless of path
        #expect(UUID(uuidString: item.id) != nil)
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

        // Each MenuItem has unique UUID, so set should have 2 elements
        // This is intentional to support items with the same title
        #expect(set.count == 2)
    }

    // MARK: - CommandType Tests

    @Test
    func testDefaultTypeIsWindow() {
        let element = createDummyElement()
        let item = MenuItem(
            title: "New",
            path: ["File", "New"],
            keyboardShortcut: nil,
            axElement: element,
            isEnabled: true
        )

        #expect(item.type == .window)
    }

    @Test
    func testExplicitTypeAssignment() {
        let element = createDummyElement()

        let windowItem = MenuItem(
            title: "Library",
            path: ["Music", "Library"],
            keyboardShortcut: nil,
            axElement: element,
            isEnabled: true,
            type: .window
        )

        #expect(windowItem.type == .window)
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
