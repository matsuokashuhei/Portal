//
//  ScrollBehaviorUITests.swift
//  PortalUITests
//
//  Created by Claude Code on 2026/01/01.
//

import XCTest

/// UI tests for scroll behavior during keyboard navigation.
/// These tests verify that scrolling only occurs when navigating to items outside the visible area.
final class ScrollBehaviorUITests: XCTestCase {

    // MARK: - Constants

    /// Timeout for panel appearance after app launch
    private let panelAppearanceTimeout: TimeInterval = 5.0

    /// Number of mock menu items to create
    private let mockItemCount = 30

    /// Small delay after keyboard navigation to allow animation to complete
    private let navigationDelay: TimeInterval = 0.2

    /// Accuracy for frame comparison (allows for floating point precision)
    private let frameAccuracy: CGFloat = 1.0

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
        XCTAssertTrue(firstItem.waitForExistence(timeout: 2.0), "Mock items should load")
    }

    // MARK: - No Scroll Tests (Within Visible Area)

    @MainActor
    func testNavigateDownWithinVisibleArea_NoScroll() throws {
        app.launch()

        let panel = app.dialogs["CommandPalettePanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: panelAppearanceTimeout))

        waitForMockItemsToLoad()

        // Record frame of first item (reference)
        let frameBefore = frameOfItem(at: 0)

        // Navigate down by 1 (from index 0 to 1)
        // Item 1 should be visible, so no scroll should occur
        pressDownArrow()
        _ = XCTWaiter().wait(for: [], timeout: navigationDelay)

        // Record frame after navigation
        let frameAfter = frameOfItem(at: 0)

        // Frames should be identical (no scroll occurred)
        XCTAssertEqual(
            frameBefore.origin.y, frameAfter.origin.y,
            accuracy: frameAccuracy,
            "First item frame should not change when navigating within visible area"
        )
    }

    @MainActor
    func testNavigateUpWithinVisibleArea_NoScroll() throws {
        app.launch()

        let panel = app.dialogs["CommandPalettePanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: panelAppearanceTimeout))

        waitForMockItemsToLoad()

        // Navigate down a few times to move away from index 0
        for _ in 0..<3 {
            pressDownArrow()
            _ = XCTWaiter().wait(for: [], timeout: 0.1)
        }

        // Now at index 3, navigate up to index 2
        let frameBefore = frameOfItem(at: 0)
        pressUpArrow()
        _ = XCTWaiter().wait(for: [], timeout: navigationDelay)
        let frameAfter = frameOfItem(at: 0)

        // Frame should not change (item 2 is visible)
        XCTAssertEqual(
            frameBefore.origin.y, frameAfter.origin.y,
            accuracy: frameAccuracy,
            "First item frame should not change when navigating up within visible area"
        )
    }

    @MainActor
    func testMultipleNavigationsWithinVisibleArea_NoScroll() throws {
        app.launch()

        let panel = app.dialogs["CommandPalettePanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: panelAppearanceTimeout))

        waitForMockItemsToLoad()

        let initialFrame = frameOfItem(at: 0)

        // Navigate down a few times, staying within visible area.
        // Panel height is ~400px, each item ~50-60px, so ~6-8 items visible.
        // Navigate 3 times to stay safely within visible area.
        for _ in 0..<3 {
            pressDownArrow()
            _ = XCTWaiter().wait(for: [], timeout: 0.1)
        }

        let frameAfterDown = frameOfItem(at: 0)
        XCTAssertEqual(
            initialFrame.origin.y, frameAfterDown.origin.y,
            accuracy: frameAccuracy,
            "Frame should not change after navigating within visible area"
        )

        // Navigate back up
        for _ in 0..<3 {
            pressUpArrow()
            _ = XCTWaiter().wait(for: [], timeout: 0.1)
        }

        let frameAfterUp = frameOfItem(at: 0)
        XCTAssertEqual(
            initialFrame.origin.y, frameAfterUp.origin.y,
            accuracy: frameAccuracy,
            "Frame should not change after navigating back up within visible area"
        )
    }

    // MARK: - Scroll Tests (Outside Visible Area)

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
