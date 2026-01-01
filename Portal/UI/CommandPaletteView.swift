//
//  CommandPaletteView.swift
//  Portal
//
//  Created by Claude Code on 2025/12/30.
//

import SwiftUI

struct CommandPaletteView: View {
    @StateObject private var viewModel = CommandPaletteViewModel()

    var body: some View {
        VStack(spacing: 0) {
            SearchFieldView(text: $viewModel.searchText)
                .padding()

            Divider()

            ResultsListView(
                results: viewModel.results,
                selectedIndex: $viewModel.selectedIndex,
                onItemClicked: { index in
                    viewModel.executeCommand(at: index)
                }
            )
            .frame(maxHeight: .infinity)
        }
        .frame(width: PanelController.panelSize.width, height: PanelController.panelSize.height)
        .overlay(alignment: .bottom) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.1))
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityLabel("Error: \(errorMessage)")
            }
        }
        .background(VisualEffectBlur())
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("CommandPaletteView")
    }
}
