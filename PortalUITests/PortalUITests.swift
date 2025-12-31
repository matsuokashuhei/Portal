//
//  PortalUITests.swift
//  PortalUITests
//
//  Created by 松岡周平 on 2025/12/29.
//

import XCTest

final class PortalUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        // Configure launch arguments for testing
        app.launchArguments = [
            "--show-panel-on-launch",
            "--skip-accessibility-check",
            "--disable-panel-auto-hide"
        ]
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Panel Tests

    @MainActor
    func testEscapeKeyHidesPanel() throws {
        app.launch()

        // NSPanel is recognized as Dialog in accessibility hierarchy
        let panelDialog = app.dialogs["CommandPalettePanel"]
        XCTAssertTrue(panelDialog.waitForExistence(timeout: 5))

        // Press Escape key
        panelDialog.typeKey(.escape, modifierFlags: [])

        // Wait for panel to disappear
        let disappeared = panelDialog.waitForNonExistence(timeout: 2)
        XCTAssertTrue(disappeared, "Panel should hide when Escape key is pressed")
    }

    // MARK: - Search Field Tests

    @MainActor
    func testSearchFieldExists() throws {
        app.launch()

        let panelDialog = app.dialogs["CommandPalettePanel"]
        XCTAssertTrue(panelDialog.waitForExistence(timeout: 5))

        // Search field is the first text field in the panel
        let searchTextField = panelDialog.textFields.firstMatch
        XCTAssertTrue(searchTextField.exists, "SearchTextField should exist in CommandPaletteView")
    }

    @MainActor
    func testSearchFieldHasPlaceholder() throws {
        app.launch()

        let panelDialog = app.dialogs["CommandPalettePanel"]
        XCTAssertTrue(panelDialog.waitForExistence(timeout: 5))

        // Find the text field (first text field in dialog)
        let searchTextField = panelDialog.textFields.firstMatch
        XCTAssertTrue(searchTextField.exists, "SearchTextField should exist")

        // Check placeholder text
        let placeholderValue = searchTextField.placeholderValue
        XCTAssertEqual(placeholderValue, "Search commands...", "Search field should have correct placeholder text")
    }

    @MainActor
    func testSearchFieldHasFocusOnLaunch() throws {
        app.launch()

        let panelDialog = app.dialogs["CommandPalettePanel"]
        XCTAssertTrue(panelDialog.waitForExistence(timeout: 5))

        let searchTextField = panelDialog.textFields.firstMatch
        XCTAssertTrue(searchTextField.exists)

        // Wait for the search field to gain keyboard focus
        let focusExpectation = expectation(
            for: NSPredicate(format: "hasKeyboardFocus == true"),
            evaluatedWith: searchTextField
        )
        wait(for: [focusExpectation], timeout: 2.0)

        // Type directly without clicking - if focused, text should appear
        searchTextField.typeText("focus test")

        // Verify text was entered (proves field had focus)
        XCTAssertEqual(searchTextField.value as? String, "focus test", "Search field should have focus on launch")
    }

    @MainActor
    func testSearchFieldAcceptsInput() throws {
        app.launch()

        let panelDialog = app.dialogs["CommandPalettePanel"]
        XCTAssertTrue(panelDialog.waitForExistence(timeout: 5))

        let searchTextField = panelDialog.textFields.firstMatch
        XCTAssertTrue(searchTextField.exists)

        // Type text into search field (field should already have focus from panel open)
        searchTextField.typeText("test query")

        // Verify the text was entered
        XCTAssertEqual(searchTextField.value as? String, "test query", "Search field should accept text input")
    }

    // MARK: - Results List Tests

    @MainActor
    func testResultsListExists() throws {
        app.launch()

        let panelDialog = app.dialogs["CommandPalettePanel"]
        XCTAssertTrue(panelDialog.waitForExistence(timeout: 5))

        // Results list is a scroll view in the panel
        let scrollView = panelDialog.scrollViews.firstMatch
        XCTAssertTrue(scrollView.exists, "ResultsListView (ScrollView) should exist in CommandPaletteView")
    }

    // MARK: - CommandPaletteView Tests

    @MainActor
    func testCommandPaletteViewExists() throws {
        app.launch()

        let panelDialog = app.dialogs["CommandPalettePanel"]
        XCTAssertTrue(panelDialog.waitForExistence(timeout: 5))

        // CommandPaletteView contains the panel content (Group in accessibility hierarchy)
        let group = panelDialog.groups.firstMatch
        XCTAssertTrue(group.exists, "CommandPaletteView (Group) should exist")
    }
}

// MARK: - XCUIElement Extension

extension XCUIElement {
    /// Waits for the element to not exist within the specified timeout.
    /// - Parameter timeout: Maximum time to wait in seconds.
    /// - Returns: `true` if the element no longer exists, `false` if timeout expired.
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }
}
