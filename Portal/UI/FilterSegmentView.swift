//
//  FilterSegmentView.swift
//  Portal
//
//  Created by Claude Code on 2026/01/02.
//

import SwiftUI

/// Spotlight-style segment control for filtering command items by type.
struct FilterSegmentView: View {
    /// Currently selected filter, used for rendering selection state.
    let selectedFilter: CommandTypeFilter

    /// Modifier key symbol to display in shortcuts (e.g., "⌘", "⌥").
    let modifierSymbol: String

    /// Called when a filter button is tapped.
    /// The parent view is responsible for applying toggle logic and state updates.
    let onFilterTapped: (CommandTypeFilter) -> Void

    var body: some View {
        HStack(spacing: 8) {
            FilterButton(
                title: "All",
                shortcut: nil,
                isSelected: selectedFilter == .all,
                action: { onFilterTapped(.all) }
            )
            FilterButton(
                title: "Menus",
                shortcut: "\(modifierSymbol)1",
                isSelected: selectedFilter == .menu,
                action: { onFilterTapped(.menu) }
            )
            FilterButton(
                title: "Window",
                shortcut: "\(modifierSymbol)2",
                isSelected: selectedFilter == .window,
                action: { onFilterTapped(.window) }
            )
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// Button for a single filter option with optional keyboard shortcut display.
private struct FilterButton: View {
    let title: String
    let shortcut: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if let shortcut = shortcut {
                    Text(shortcut)
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .foregroundColor(isSelected ? .accentColor : .primary)
    }
}
