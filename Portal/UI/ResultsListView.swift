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

    /// Stores the frame of the scroll view's visible area in global coordinates.
    @State private var scrollViewFrame: CGRect = .zero
    /// Stores the frame of each item in global coordinates.
    @State private var itemFrames: [Int: CGRect] = [:]
    /// Tracks the last navigation direction for scroll anchor calculation.
    @State private var lastNavigationDirection: NavigationDirection?

    private enum NavigationDirection {
        case up, down
    }

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
                                    if isHovering, selectedIndex != index {
                                        selectedIndex = index
                                    }
                                }
                                .background(
                                    GeometryReader { geometry in
                                        Color.clear.preference(
                                            key: ItemFramePreferenceKey.self,
                                            value: [index: geometry.frame(in: .global)]
                                        )
                                    }
                                )
                                .accessibilityLabel(
                                    buildAccessibilityLabel(item: item, index: index, isSelected: isSelected)
                                )
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }
            }
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ScrollViewFramePreferenceKey.self,
                        value: geometry.frame(in: .global)
                    )
                }
            )
            .onPreferenceChange(ScrollViewFramePreferenceKey.self) { frame in
                scrollViewFrame = frame
            }
            .onPreferenceChange(ItemFramePreferenceKey.self) { frames in
                itemFrames.merge(frames) { _, new in new }
            }
            // Only scroll on keyboard navigation, not on hover selection
            .onReceive(NotificationCenter.default.publisher(for: .navigateUp)) { _ in
                lastNavigationDirection = .up
                scrollToSelectedIfNeeded(proxy: proxy)
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateDown)) { _ in
                lastNavigationDirection = .down
                scrollToSelectedIfNeeded(proxy: proxy)
            }
        }
        .accessibilityIdentifier("ResultsListView")
    }

    private func scrollToSelectedIfNeeded(proxy: ScrollViewProxy) {
        // Defer scroll to next run loop to ensure ViewModel has updated selectedIndex
        DispatchQueue.main.async {
            guard selectedIndex >= 0, selectedIndex < results.count else { return }
            guard let itemFrame = itemFrames[selectedIndex] else { return }

            // Check if item is already fully visible
            let isVisible = scrollViewFrame.contains(itemFrame)
            guard !isVisible else { return }

            // Scroll with minimal movement: place item at edge of scroll direction
            let anchor: UnitPoint
            switch lastNavigationDirection {
            case .down:
                anchor = .bottom  // Item appears at bottom edge (minimal scroll down)
            case .up:
                anchor = .top     // Item appears at top edge (minimal scroll up)
            case .none:
                anchor = .center
            }

            withAnimation(.easeInOut(duration: 0.15)) {
                proxy.scrollTo(selectedIndex, anchor: anchor)
            }
        }
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

// MARK: - Preference Keys for Scroll Visibility Detection

/// Preference key for tracking the scroll view's visible frame.
private struct ScrollViewFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// Preference key for tracking individual item frames.
private struct ItemFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
