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
    private var cancellables = Set<AnyCancellable>()
    private var loadMenuItemsTask: Task<Void, Never>?

    /// Debounce interval for search.
    static let searchDebounceInterval: Int = 50

    init() {
        setupNotificationObserver()
        setupSearchDebounce()
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

    /// Loads menu items from the specified application.
    ///
    /// - Parameter app: The application to crawl menus from. If `nil`, attempts to crawl the
    ///   frontmost non-Portal application as determined by `MenuCrawler.crawlActiveApplication()`.
    ///   If Portal is the only regular running app, this may result in a `noActiveApplication` error.
    func loadMenuItems(for app: NSRunningApplication?) {
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
                let targetApp = notification.userInfo?[NotificationUserInfoKey.targetApp] as? NSRunningApplication
                self?.loadMenuItems(for: targetApp)
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
        if query.isEmpty {
            filteredResults = []
        } else {
            filteredResults = FuzzySearch.search(query: query, in: menuItems)
        }
        if resetSelection {
            selectedIndex = 0
        }
    }
}
