//
//  CommandPaletteViewModelTests.swift
//  PortalTests
//
//  Created by Claude Code on 2025/12/31.
//

import Testing
@testable import Portal

struct CommandPaletteViewModelTests {

    @Test @MainActor
    func testInitialSearchTextIsEmpty() {
        let viewModel = CommandPaletteViewModel()
        #expect(viewModel.searchText == "")
    }

    @Test @MainActor
    func testInitialSelectedIndexIsZero() {
        let viewModel = CommandPaletteViewModel()
        #expect(viewModel.selectedIndex == 0)
    }

    @Test @MainActor
    func testInitialResultsIsEmpty() {
        let viewModel = CommandPaletteViewModel()
        #expect(viewModel.results.isEmpty)
    }

    @Test @MainActor
    func testClearSearchResetsSearchText() {
        let viewModel = CommandPaletteViewModel()
        viewModel.searchText = "test query"
        viewModel.clearSearch()
        #expect(viewModel.searchText == "")
    }

    @Test @MainActor
    func testClearSearchResetsSelectedIndex() {
        let viewModel = CommandPaletteViewModel()
        viewModel.selectedIndex = 5
        viewModel.clearSearch()
        #expect(viewModel.selectedIndex == 0)
    }

    @Test @MainActor
    func testInitialMenuItemsIsEmpty() {
        let viewModel = CommandPaletteViewModel()
        #expect(viewModel.menuItems.isEmpty)
    }

    @Test @MainActor
    func testInitialIsLoadingIsFalse() {
        let viewModel = CommandPaletteViewModel()
        #expect(viewModel.isLoading == false)
    }

    @Test @MainActor
    func testInitialErrorMessageIsNil() {
        let viewModel = CommandPaletteViewModel()
        #expect(viewModel.errorMessage == nil)
    }

    // MARK: - Navigation Tests
    // Note: Testing with actual results requires MenuItem with AXUIElement (not mockable).
    // Full navigation behavior is tested via UI tests and manual testing.

    @Test @MainActor
    func testMoveSelectionUpWithEmptyResultsDoesNothing() {
        let viewModel = CommandPaletteViewModel()
        viewModel.selectedIndex = 0
        viewModel.moveSelectionUp()
        #expect(viewModel.selectedIndex == 0)
    }

    @Test @MainActor
    func testMoveSelectionDownWithEmptyResultsDoesNothing() {
        let viewModel = CommandPaletteViewModel()
        viewModel.selectedIndex = 0
        viewModel.moveSelectionDown()
        #expect(viewModel.selectedIndex == 0)
    }

    @Test @MainActor
    func testExecuteSelectedCommandWithEmptyResultsDoesNothing() {
        let viewModel = CommandPaletteViewModel()
        viewModel.executeSelectedCommand()
        #expect(viewModel.errorMessage == nil)
    }

    @Test @MainActor
    func testExecuteCommandAtInvalidIndexDoesNothing() {
        let viewModel = CommandPaletteViewModel()
        viewModel.executeCommand(at: -1)
        #expect(viewModel.errorMessage == nil)
        viewModel.executeCommand(at: 100)
        #expect(viewModel.errorMessage == nil)
    }
}
