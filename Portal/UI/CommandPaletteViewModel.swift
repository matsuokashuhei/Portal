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

    private let menuCrawler = MenuCrawler()
    private var cancellables = Set<AnyCancellable>()
    private var loadMenuItemsTask: Task<Void, Never>?

    init() {
        setupNotificationObserver()
    }

    deinit {
        loadMenuItemsTask?.cancel()
    }

    // TODO: Implement command search/filtering based on `searchText` (Issue #49)
    var results: [MenuItem] {
        menuItems
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

            isLoading = false
        }
    }

    // MARK: - Private Methods

    private func setupNotificationObserver() {
        NotificationCenter.default.publisher(for: .panelDidShow)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                let targetApp = notification.userInfo?[NotificationUserInfoKey.targetApp] as? NSRunningApplication
                self?.loadMenuItems(for: targetApp)
            }
            .store(in: &cancellables)
    }
}
