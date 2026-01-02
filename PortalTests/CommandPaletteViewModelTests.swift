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

    // MARK: - Error Clearing Tests

    @Test @MainActor
    func testMoveSelectionDownClearsErrorMessage() {
        let viewModel = CommandPaletteViewModel()
        // Add mock items to enable navigation
        viewModel.menuItems = MockMenuItemFactory.createMockItems(count: 3)
        viewModel.selectedIndex = 0
        // Set an error to simulate a previous failed execution
        viewModel.errorMessage = "Test error"

        viewModel.moveSelectionDown()

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.selectedIndex == 1)
    }

    @Test @MainActor
    func testMoveSelectionUpClearsErrorMessage() {
        let viewModel = CommandPaletteViewModel()
        viewModel.menuItems = MockMenuItemFactory.createMockItems(count: 3)
        viewModel.selectedIndex = 2
        viewModel.errorMessage = "Test error"

        viewModel.moveSelectionUp()

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.selectedIndex == 1)
    }

    // MARK: - MockMenuItemFactory Tests

    @Test @MainActor
    func testMockMenuItemFactoryCreatesAllEnabledByDefault() {
        let items = MockMenuItemFactory.createMockItems(count: 5)
        #expect(items.count == 5)
        #expect(items.allSatisfy { $0.isEnabled })
    }

    @Test @MainActor
    func testMockMenuItemFactoryCreatesDisabledItems() {
        let items = MockMenuItemFactory.createMockItems(count: 5, disabledIndices: [1, 3])
        #expect(items.count == 5)
        #expect(items[0].isEnabled == true)
        #expect(items[1].isEnabled == false)
        #expect(items[2].isEnabled == true)
        #expect(items[3].isEnabled == false)
        #expect(items[4].isEnabled == true)
    }

    @Test @MainActor
    func testFilteringDisabledItems() {
        // Simulate what loadItems does: filter disabled items
        let allItems = MockMenuItemFactory.createMockItems(count: 5, disabledIndices: [1, 3])
        let filteredItems = allItems.filter { $0.isEnabled }

        #expect(filteredItems.count == 3)
        #expect(filteredItems.allSatisfy { $0.isEnabled })
    }

    // MARK: - Results Order Tests

    @Test @MainActor
    func testResultsPreservesMenuItemsOrderWhenSearchTextIsEmpty() {
        let viewModel = CommandPaletteViewModel()
        let items = MockMenuItemFactory.createMockItems(count: 5)
        viewModel.menuItems = items

        #expect(viewModel.searchText.isEmpty)
        #expect(viewModel.results.count == items.count)
        for (index, item) in viewModel.results.enumerated() {
            #expect(item.title == items[index].title)
        }
    }

    // MARK: - Type Filter Tests

    @Test @MainActor
    func testInitialTypeFilterIsAll() {
        let viewModel = CommandPaletteViewModel()
        #expect(viewModel.typeFilter == .all)
    }

    @Test @MainActor
    func testToggleTypeFilterToMenu() {
        let viewModel = CommandPaletteViewModel()
        viewModel.toggleTypeFilter(.menu)
        #expect(viewModel.typeFilter == .menu)
    }

    @Test @MainActor
    func testToggleTypeFilterToSidebar() {
        let viewModel = CommandPaletteViewModel()
        viewModel.toggleTypeFilter(.sidebar)
        #expect(viewModel.typeFilter == .sidebar)
    }

    @Test @MainActor
    func testToggleTypeFilterFromMenuToAll() {
        let viewModel = CommandPaletteViewModel()
        viewModel.typeFilter = .menu
        viewModel.toggleTypeFilter(.menu)
        #expect(viewModel.typeFilter == .all)
    }

    @Test @MainActor
    func testToggleTypeFilterFromSidebarToAll() {
        let viewModel = CommandPaletteViewModel()
        viewModel.typeFilter = .sidebar
        viewModel.toggleTypeFilter(.sidebar)
        #expect(viewModel.typeFilter == .all)
    }

    @Test @MainActor
    func testResultsFilteredByMenuType() {
        let viewModel = CommandPaletteViewModel()
        let menuItems = MockMenuItemFactory.createMockItems(count: 3, type: .menu)
        let sidebarItems = MockMenuItemFactory.createMockItems(count: 2, type: .sidebar)
        viewModel.menuItems = menuItems + sidebarItems

        viewModel.typeFilter = .menu

        #expect(viewModel.results.count == 3)
        #expect(viewModel.results.allSatisfy { $0.type == .menu })
    }

    @Test @MainActor
    func testResultsFilteredBySidebarType() {
        let viewModel = CommandPaletteViewModel()
        let menuItems = MockMenuItemFactory.createMockItems(count: 3, type: .menu)
        let sidebarItems = MockMenuItemFactory.createMockItems(count: 2, type: .sidebar)
        viewModel.menuItems = menuItems + sidebarItems

        viewModel.typeFilter = .sidebar

        #expect(viewModel.results.count == 2)
        #expect(viewModel.results.allSatisfy { $0.type == .sidebar })
    }

    @Test @MainActor
    func testResultsShowAllTypesWhenFilterIsAll() {
        let viewModel = CommandPaletteViewModel()
        let menuItems = MockMenuItemFactory.createMockItems(count: 3, type: .menu)
        let sidebarItems = MockMenuItemFactory.createMockItems(count: 2, type: .sidebar)
        viewModel.menuItems = menuItems + sidebarItems

        viewModel.typeFilter = .all

        #expect(viewModel.results.count == 5)
    }

    @Test @MainActor
    func testToggleTypeFilterResetsSelectedIndex() {
        let viewModel = CommandPaletteViewModel()
        viewModel.menuItems = MockMenuItemFactory.createMockItems(count: 5)
        viewModel.selectedIndex = 3

        viewModel.toggleTypeFilter(.menu)

        #expect(viewModel.selectedIndex == 0)
    }

    @Test @MainActor
    func testToggleTypeFilterFromMenuToSidebar() {
        let viewModel = CommandPaletteViewModel()
        viewModel.typeFilter = .menu
        viewModel.toggleTypeFilter(.sidebar)
        #expect(viewModel.typeFilter == .sidebar)
    }
}
