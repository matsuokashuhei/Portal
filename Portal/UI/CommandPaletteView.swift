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
        .onAppear {
            isSearchFieldFocused = true
        }
    }
}
