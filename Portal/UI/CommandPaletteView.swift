//
//  CommandPaletteView.swift
//  Portal
//
//  Created by Claude Code on 2025/12/30.
//

import SwiftUI

struct CommandPaletteView: View {
    @StateObject private var viewModel = CommandPaletteViewModel()
    @FocusState private var isSearchFieldFocused: Bool

    private let panelDidBecomeKey = NotificationCenter.default
        .publisher(for: .panelDidBecomeKey)

    var body: some View {
        VStack(spacing: 0) {
            SearchFieldView(text: $viewModel.searchText, isFocused: $isSearchFieldFocused)
                .padding()

            Divider()

            ResultsListView(results: viewModel.results, selectedIndex: viewModel.selectedIndex)
                .frame(maxHeight: .infinity)
        }
        .frame(width: PanelController.panelSize.width, height: PanelController.panelSize.height)
        .background(VisualEffectBlur())
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("CommandPaletteView")
        .onReceive(panelDidBecomeKey) { _ in
            isSearchFieldFocused = true
        }
    }
}
