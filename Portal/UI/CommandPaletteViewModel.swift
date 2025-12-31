//
//  CommandPaletteViewModel.swift
//  Portal
//
//  Created by Claude Code on 2025/12/30.
//

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

    init() {
        setupNotificationObserver()
    }

    // TODO: Implement command search/filtering based on `searchText` (Issue #49)
    var results: [MenuItem] {
        menuItems
    }

    func clearSearch() {
        searchText = ""
        selectedIndex = 0
    }

    /// Loads menu items from the active application.
    func loadMenuItemsForActiveApp() {
        Task {
            isLoading = true
            errorMessage = nil

            do {
                let items = try await menuCrawler.crawlActiveApplication()
                menuItems = items
            } catch {
                errorMessage = error.localizedDescription
                menuItems = []
            }

            isLoading = false
        }
    }

    // MARK: - Private Methods

    private func setupNotificationObserver() {
        NotificationCenter.default.publisher(for: .panelDidShow)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadMenuItemsForActiveApp()
            }
            .store(in: &cancellables)
    }
}
