//
//  ScrollBehaviorUITests.swift
//  PortalUITests
//
//  Created by Claude Code on 2026/01/01.
//

import XCTest

/// UI tests for scroll behavior during keyboard navigation.
/// These tests verify that scrolling works correctly when navigating through the results list.
final class ScrollBehaviorUITests: XCTestCase {

    // MARK: - Constants

    /// Timeout for panel appearance after app launch
    private let panelAppearanceTimeout: TimeInterval = 5.0

    /// Timeout for mock menu items to appear after panel shows.
    /// Shorter than panel appearance since items load quickly after panel is visible.
    private let mockItemsLoadTimeout: TimeInterval = 2.0

    /// Number of mock menu items to create
    private let mockItemCount = 30

    /// Small delay after keyboard navigation to allow animation to complete
    private let navigationDelay: TimeInterval = 0.2

    // MARK: - Properties

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = [
            "--show-panel-on-launch",
            "--skip-accessibility-check",
            "--disable-panel-auto-hide",
            "--use-mock-menu-items=\(mockItemCount)"
        ]
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Test Helpers

    /// Returns the frame of the specified result item.
    private func frameOfItem(at index: Int) -> CGRect {
        let panel = app.dialogs["CommandPalettePanel"]
        let item = panel.descendants(matching: .any)
            .matching(identifier: "ResultItem_\(index)")
            .firstMatch
        return item.frame
    }

    /// Presses the down arrow key.
    private func pressDownArrow() {
        let panel = app.dialogs["CommandPalettePanel"]
        panel.typeKey(.downArrow, modifierFlags: [])
    }

    /// Presses the up arrow key.
    private func pressUpArrow() {
        let panel = app.dialogs["CommandPalettePanel"]
        panel.typeKey(.upArrow, modifierFlags: [])
    }

    /// Waits for mock items to load by checking for the first item.
    private func waitForMockItemsToLoad() {
        let firstItem = app.descendants(matching: .any)
            .matching(identifier: "ResultItem_0")
            .firstMatch
        XCTAssertTrue(firstItem.waitForExistence(timeout: mockItemsLoadTimeout), "Mock items should load")
    }

    // MARK: - Scroll Tests

    @MainActor
    func testNavigateToItemOutsideVisibleArea_ScrollOccurs() throws {
        app.launch()

        let panel = app.dialogs["CommandPalettePanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: panelAppearanceTimeout))

        waitForMockItemsToLoad()

        let initialFrame = frameOfItem(at: 0)

        // Navigate down many times to reach items outside visible area
        // With 30 items and ~8-10 visible, navigating 15+ times should trigger scroll
        for _ in 0..<15 {
            pressDownArrow()
            _ = XCTWaiter().wait(for: [], timeout: 0.05)
        }

        // Allow animation to complete
        _ = XCTWaiter().wait(for: [], timeout: 0.3)

        let frameAfterScroll = frameOfItem(at: 0)

        // The first item's frame should have changed (scrolled)
        XCTAssertNotEqual(
            initialFrame.origin.y, frameAfterScroll.origin.y,
            "First item frame should change when scrolling to items outside visible area"
        )
    }

    @MainActor
    func testScrollUpToItemAboveVisibleArea_ScrollOccurs() throws {
        app.launch()

        let panel = app.dialogs["CommandPalettePanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: panelAppearanceTimeout))

        waitForMockItemsToLoad()

        // Navigate down far enough to scroll
        for _ in 0..<20 {
            pressDownArrow()
            _ = XCTWaiter().wait(for: [], timeout: 0.05)
        }
        _ = XCTWaiter().wait(for: [], timeout: 0.3)

        // Record frame after scrolling down
        let frameAfterScrollDown = frameOfItem(at: 0)

        // Navigate back up to the beginning
        for _ in 0..<20 {
            pressUpArrow()
            _ = XCTWaiter().wait(for: [], timeout: 0.05)
        }
        _ = XCTWaiter().wait(for: [], timeout: 0.3)

        let frameAfterScrollUp = frameOfItem(at: 0)

        // Frame should have changed (scrolled back to show first item)
        XCTAssertNotEqual(
            frameAfterScrollDown.origin.y, frameAfterScrollUp.origin.y,
            "First item frame should change when scrolling back up"
        )
    }
}
