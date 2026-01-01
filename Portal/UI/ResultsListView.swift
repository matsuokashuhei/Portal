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
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onItemClicked?(index)
                                }
                                .onHover { isHovering in
                                    if isHovering {
                                        selectedIndex = index
                                    }
                                }
                                .accessibilityLabel(
                                    buildAccessibilityLabel(item: item, index: index, isSelected: isSelected)
                                )
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }
            }
            .onChange(of: selectedIndex) { _, newValue in
                guard newValue >= 0, newValue < results.count else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .accessibilityIdentifier("ResultsListView")
    }

    /// Builds a comprehensive accessibility label for VoiceOver users.
    /// Uses pathString instead of title to avoid redundancy (title is the last element of path).
    private func buildAccessibilityLabel(item: MenuItem, index: Int, isSelected: Bool) -> String {
        var components: [String] = [item.pathString]

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

    var body: some View {
        HStack {
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
                : Color.clear
        )
        .cornerRadius(6)
        .opacity(item.isEnabled ? 1.0 : 0.5)
    }
}
