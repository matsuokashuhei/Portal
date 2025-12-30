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

    // TODO: Implement command search/filtering based on `searchText` (Issue #49)
    var results: [String] {
        []
    }

    func clearSearch() {
        searchText = ""
        selectedIndex = 0
    }
}
