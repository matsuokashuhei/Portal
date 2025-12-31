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
    func testInitialSearchTextIsEmpty() async throws {
        let viewModel = CommandPaletteViewModel()
        #expect(viewModel.searchText == "")
    }

    @Test @MainActor
    func testInitialSelectedIndexIsZero() async throws {
        let viewModel = CommandPaletteViewModel()
        #expect(viewModel.selectedIndex == 0)
    }

    @Test @MainActor
    func testInitialResultsIsEmpty() async throws {
        let viewModel = CommandPaletteViewModel()
        #expect(viewModel.results.isEmpty)
    }

    @Test @MainActor
    func testClearSearchResetsSearchText() async throws {
        let viewModel = CommandPaletteViewModel()
        viewModel.searchText = "test query"
        viewModel.clearSearch()
        #expect(viewModel.searchText == "")
    }

    @Test @MainActor
    func testClearSearchResetsSelectedIndex() async throws {
        let viewModel = CommandPaletteViewModel()
        viewModel.selectedIndex = 5
        viewModel.clearSearch()
        #expect(viewModel.selectedIndex == 0)
    }
}
