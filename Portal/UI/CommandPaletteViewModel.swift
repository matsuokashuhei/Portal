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
    private let windowCrawler = WindowCrawler()
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
        guard selectedIndex > 0 else { return }

        errorMessage = nil
        selectedIndex -= 1
    }

    /// Moves selection down by one item. Does nothing if already at the bottom.
    func moveSelectionDown() {
        guard !results.isEmpty, selectedIndex < results.count - 1 else { return }

        errorMessage = nil
        selectedIndex += 1
    }

    // MARK: - Execution

    /// Executes the currently selected command.
    func executeSelectedCommand() {
        guard selectedIndex >= 0, selectedIndex < results.count else {
            #if DEBUG
            print("[CommandPaletteViewModel] executeSelectedCommand: invalid selectedIndex=\(selectedIndex), results.count=\(results.count)")
            #endif
            return
        }
        executeCommand(at: selectedIndex)
    }

    /// Executes the command at the specified index.
    func executeCommand(at index: Int) {
        guard index >= 0, index < results.count else {
            #if DEBUG
            print("[CommandPaletteViewModel] executeCommand: invalid index=\(index), results.count=\(results.count)")
            #endif
            return
        }

        let menuItem = results[index]
        let result = commandExecutor.execute(menuItem)

        switch result {
        case .success:
            errorMessage = nil
            NotificationCenter.default.post(
                name: .hidePanel,
                object: nil,
                userInfo: [NotificationUserInfoKey.restoreFocus: true]
            )
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    /// Loads menu items and sidebar elements from the specified application.
    ///
    /// Menu items are loaded first and displayed immediately, then sidebar elements are loaded
    /// and appended to the list. This provides a responsive user experience while still
    /// including all available commands.
    ///
    /// - Parameter app: The application to crawl from. If `nil`, attempts to crawl the
    ///   frontmost non-Portal application as determined by `MenuCrawler.crawlActiveApplication()`.
    ///   If Portal is the only regular running app, this may result in a `noActiveApplication` error.
    ///
    /// - Note: In test mode with `--use-mock-menu-items=<count>`, mock items are used instead of
    ///   real crawling. This enables UI testing of scroll behavior with predictable data.
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

            var allItems: [MenuItem] = []

            // Step 1: Load menu items first (fast, commonly used)
            do {
                let menuItemsResult: [MenuItem]
                if let targetApp = app {
                    menuItemsResult = try await menuCrawler.crawlApplication(targetApp)
                } else {
                    menuItemsResult = try await menuCrawler.crawlActiveApplication()
                }

                // Check for cancellation before updating state
                guard !Task.isCancelled else { return }

                allItems = menuItemsResult.filter { $0.isEnabled }
                menuItems = allItems
                selectedIndex = 0
            } catch {
                // Check for cancellation before updating state
                guard !Task.isCancelled else { return }

                errorMessage = error.localizedDescription
                menuItems = []
                selectedIndex = 0
                return
            }

            // Step 2: Load sidebar elements (may take longer, append to existing)
            // Failures are silently ignored - menus alone are sufficient
            if let targetApp = app {
                do {
                    let sidebarItems = try await windowCrawler.crawlSidebarElements(targetApp)

                    // Check for cancellation before updating state
                    guard !Task.isCancelled else { return }

                    let enabledSidebarItems = sidebarItems.filter { $0.isEnabled }
                    if !enabledSidebarItems.isEmpty {
                        allItems.append(contentsOf: enabledSidebarItems)
                        menuItems = allItems
                    }
                } catch {
                    // Sidebar crawling failures are non-fatal; menu items are already displayed
                    #if DEBUG
                    print("[CommandPaletteViewModel] Sidebar crawling failed: \(error.localizedDescription)")
                    #endif
                }
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
    /// Supporting multiple independent instances would require broader architectural changes
    /// (e.g., instance-specific notification identifiers or a delegate/closure-based API),
    /// not just injecting a different NotificationCenter, since notification names are global.
    ///
    /// ## Lifecycle
    /// This method is called exactly once from init(). The observers are stored in `cancellables`
    /// and cleaned up automatically on deinit via AnyCancellable's behavior.
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
