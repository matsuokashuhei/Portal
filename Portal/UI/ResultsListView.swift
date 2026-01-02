//
//  ResultsListView.swift
//  Portal
//
//  Created by Claude Code on 2025/12/30.
//

import SwiftUI

struct ResultsListView: View {
    var results: [MenuItem]
    @Binding var selectedIndex: Int
    var onItemClicked: ((Int) -> Void)?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if results.isEmpty {
                        Text("Type to search commands...")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        ForEach(results.indices, id: \.self) { index in
                            let item = results[index]
                            let isSelected = index == selectedIndex
                            MenuItemRow(item: item, isSelected: isSelected)
                                .id(index)
                                .accessibilityIdentifier("ResultItem_\(index)")
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onItemClicked?(index)
                                }
                                .accessibilityLabel(
                                    buildAccessibilityLabel(item: item, index: index, isSelected: isSelected)
                                )
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }
            }
            // Keyboard navigation scroll: notification handlers calculate the NEW target index
            // using selectedIndex ± 1 BEFORE ViewModel updates the state. This allows animation
            // to start immediately. Example: if selectedIndex=5, navigateDown scrolls to 6.
            .onReceive(NotificationCenter.default.publisher(for: .navigateUp)) { _ in
                scrollToIndex(selectedIndex - 1, proxy: proxy)
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateDown)) { _ in
                scrollToIndex(selectedIndex + 1, proxy: proxy)
            }
            // Safety net for rapid key presses: ensures final position is correct without animation
            .onChange(of: selectedIndex) { _, newIndex in
                guard newIndex >= 0, newIndex < results.count else { return }
                proxy.scrollTo(newIndex)
            }
        }
        .accessibilityIdentifier("ResultsListView")
    }

    private func scrollToIndex(_ index: Int, proxy: ScrollViewProxy) {
        guard index >= 0, index < results.count else { return }

        withAnimation(.easeInOut(duration: 0.15)) {
            proxy.scrollTo(index)
        }
    }

    /// Builds a comprehensive accessibility label for VoiceOver users.
    /// Uses pathString instead of title to avoid redundancy (title is the last element of path).
    private func buildAccessibilityLabel(item: MenuItem, index: Int, isSelected: Bool) -> String {
        var components: [String] = []

        // Add type indicator
        components.append(accessibleTypeName(for: item.type))

        // Add path
        components.append(item.pathString)

        if let shortcut = item.keyboardShortcut {
            let spokenShortcut = convertShortcutToSpokenText(shortcut)
            components.append("shortcut \(spokenShortcut)")
        }

        if !item.isEnabled {
            components.append("disabled")
        }

        components.append("Result \(index + 1) of \(results.count)")

        if isSelected {
            components.append("selected")
        }

        return components.joined(separator: ", ")
    }

    /// Returns the accessible name for a command type.
    private func accessibleTypeName(for type: CommandType) -> String {
        switch type {
        case .menu:
            return "Menu item"
        case .window:
            return "Window item"
        }
    }

    /// Converts keyboard shortcut symbols to VoiceOver-friendly spoken text.
    /// For example: "⌃⌥⇧⌘N" → "Control Option Shift Command N"
    private func convertShortcutToSpokenText(_ shortcut: String) -> String {
        let symbolMap: [Character: String] = [
            "⌃": "Control",
            "⌥": "Option",
            "⇧": "Shift",
            "⌘": "Command"
        ]

        var components: [String] = []

        for character in shortcut {
            if let mapped = symbolMap[character] {
                components.append(mapped)
            } else if character != " " {
                components.append(String(character))
            }
        }

        return components.joined(separator: " ")
    }
}

// MARK: - Menu Item Row

private struct MenuItemRow: View {
    let item: MenuItem
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Type indicator icon
            Image(systemName: iconName(for: item.type))
                .font(.caption)
                .foregroundColor(iconColor(for: item.type))
                .frame(width: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .foregroundColor(item.isEnabled ? .primary : .secondary)

                if let parentPath = item.parentPathString {
                    Text(parentPath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let shortcut = item.keyboardShortcut {
                Text(shortcut)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.2)
                : isHovered
                    ? Color.secondary.opacity(0.1)
                    : Color.clear
        )
        .cornerRadius(6)
        .opacity(item.isEnabled ? 1.0 : 0.5)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    /// Returns the SF Symbol name for the given command type.
    private func iconName(for type: CommandType) -> String {
        switch type {
        case .menu:
            return "command"
        case .window:
            return "macwindow"
        }
    }

    /// Returns the icon color for the given command type.
    private func iconColor(for type: CommandType) -> Color {
        switch type {
        case .menu:
            return .secondary
        case .window:
            return .blue.opacity(0.8)
        }
    }
}
