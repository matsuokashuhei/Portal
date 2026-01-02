//
//  FilterSegmentView.swift
//  Portal
//
//  Created by Claude Code on 2026/01/02.
//

import SwiftUI

/// Spotlight-style segment control for filtering command items by type.
struct FilterSegmentView: View {
    @Binding var selectedFilter: CommandTypeFilter

    var body: some View {
        HStack(spacing: 8) {
            FilterButton(
                title: "All",
                shortcut: nil,
                isSelected: selectedFilter == .all,
                action: { selectedFilter = .all }
            )
            FilterButton(
                title: "Menus",
                shortcut: "⌘1",
                isSelected: selectedFilter == .menu,
                action: { selectedFilter = .menu }
            )
            FilterButton(
                title: "Sidebar",
                shortcut: "⌘2",
                isSelected: selectedFilter == .sidebar,
                action: { selectedFilter = .sidebar }
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
