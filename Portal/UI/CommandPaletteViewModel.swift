//
//  CommandPaletteViewModel.swift
//  Portal
//
//  Created by Claude Code on 2025/12/30.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class CommandPaletteViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var selectedIndex: Int = 0
    @Published var menuItems: [MenuItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published private(set) var filteredResults: [FuzzySearch.Match] = []

    private let menuCrawler = MenuCrawler()
    private let commandExecutor = CommandExecutor()
    private var cancellables = Set<AnyCancellable>()
    private var loadMenuItemsTask: Task<Void, Never>?

    /// Debounce interval for search.
    static let searchDebounceInterval: Int = 50

    init() {
        setupNotificationObserver()
        setupSearchDebounce()
        setupNavigationObservers()
    }

    deinit {
        loadMenuItemsTask?.cancel()
    }

    /// Filtered menu items based on search text.
    var results: [MenuItem] {
        if searchText.isEmpty {
            return menuItems
        }
        return filteredResults.map(\.item)
    }

    func clearSearch() {
        searchText = ""
        selectedIndex = 0
    }

    // MARK: - Navigation

    /// Moves selection up by one item. Does nothing if already at the top.
    func moveSelectionUp() {
        guard results.count > 0, selectedIndex > 0 else { return }

        errorMessage = nil
        selectedIndex -= 1
    }

    /// Moves selection down by one item. Does nothing if already at the bottom.
    func moveSelectionDown() {
        let count = results.count
        guard count > 0, selectedIndex < count - 1 else { return }

        errorMessage = nil
        selectedIndex += 1
    }

    // MARK: - Execution

    /// Executes the currently selected command.
    func executeSelectedCommand() {
        guard selectedIndex >= 0, selectedIndex < results.count else { return }
        executeCommand(at: selectedIndex)
    }

    /// Executes the command at the specified index.
    func executeCommand(at index: Int) {
        guard index >= 0, index < results.count else { return }

        let menuItem = results[index]
        let result = commandExecutor.execute(menuItem)

        switch result {
        case .success:
            errorMessage = nil
            NotificationCenter.default.post(name: .hidePanel, object: nil)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    /// Loads menu items from the specified application.
    ///
    /// - Parameter app: The application to crawl menus from. If `nil`, attempts to crawl the
    ///   frontmost non-Portal application as determined by `MenuCrawler.crawlActiveApplication()`.
    ///   If Portal is the only regular running app, this may result in a `noActiveApplication` error.
    ///
    /// - Note: In test mode with `--use-mock-menu-items=<count>`, mock items are used instead of
    ///   real menu crawling. This enables UI testing of scroll behavior with predictable data.
    func loadMenuItems(for app: NSRunningApplication?) {
        // In mock mode, use mock items instead of real menu crawling
        if let mockCount = TestConfiguration.mockMenuItemsCount {
            menuItems = MockMenuItemFactory.createMockItems(count: mockCount)
            selectedIndex = 0
            return
        }

        // Cancel any in-flight request to prevent race conditions
        loadMenuItemsTask?.cancel()

        loadMenuItemsTask = Task { @MainActor in
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }

            do {
                let items: [MenuItem]
                if let targetApp = app {
                    items = try await menuCrawler.crawlApplication(targetApp)
                } else {
                    items = try await menuCrawler.crawlActiveApplication()
                }

                // Check for cancellation before updating state
                guard !Task.isCancelled else { return }

                menuItems = items
                selectedIndex = 0
            } catch {
                // Check for cancellation before updating state
                guard !Task.isCancelled else { return }

                errorMessage = error.localizedDescription
                menuItems = []
                selectedIndex = 0
            }
        }
    }

    // MARK: - Private Methods

    private func setupNotificationObserver() {
        NotificationCenter.default.publisher(for: .panelDidShow)
            .sink { [weak self] notification in
                guard let self else { return }

                let targetApp = notification.userInfo?[NotificationUserInfoKey.targetApp] as? NSRunningApplication

                // Force invalidate cache for Finder to ensure fresh menu items.
                // Finder's menus change dynamically and stale references can cause
                // unintended actions (including system-level changes like resolution).
                if targetApp?.bundleIdentifier == Constants.BundleIdentifier.finder {
                    self.menuCrawler.invalidateCache()
                }

                self.loadMenuItems(for: targetApp)
            }
            .store(in: &cancellables)
    }

    private func setupSearchDebounce() {
        // Debounce search text changes and reset selection
        $searchText
            .debounce(
                for: .milliseconds(Self.searchDebounceInterval),
                scheduler: DispatchQueue.main
            )
            .removeDuplicates()
            .sink { [weak self] query in
                self?.performSearch(query: query, resetSelection: true)
            }
            .store(in: &cancellables)

        // Re-filter when menu items change (without resetting selection if user hasn't typed)
        $menuItems
            .sink { [weak self] _ in
                guard let self, !self.searchText.isEmpty else { return }
                self.performSearch(query: self.searchText, resetSelection: false)
            }
            .store(in: &cancellables)
    }

    private func performSearch(query: String, resetSelection: Bool) {
        errorMessage = nil

        if query.isEmpty {
            filteredResults = []
        } else {
            filteredResults = FuzzySearch.search(query: query, in: menuItems)
        }
        if resetSelection {
            selectedIndex = 0
        }
    }

    /// Sets up observers for keyboard navigation notifications from PanelController.
    ///
    /// ## Architecture Note
    /// Global notifications decouple PanelController (AppKit keyboard handling) from this
    /// ViewModel (SwiftUI state management), avoiding a direct dependency between layers.
    /// Portal uses a single CommandPaletteView instance, so multiple-instance concerns don't apply.
    /// If multiple instances become necessary, consider injecting a NotificationCenter instance
    /// or using a delegate pattern.
    private func setupNavigationObservers() {
        NotificationCenter.default.publisher(for: .navigateUp)
            .sink { [weak self] _ in self?.moveSelectionUp() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .navigateDown)
            .sink { [weak self] _ in self?.moveSelectionDown() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .executeSelectedCommand)
            .sink { [weak self] _ in self?.executeSelectedCommand() }
            .store(in: &cancellables)
    }
}
