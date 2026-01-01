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

    /// Height of the scroll view's visible area.
    @State private var scrollViewHeight: CGFloat = 0
    /// Stores the frame of each item in scroll view's local coordinate space.
    @State private var itemFrames: [Int: CGRect] = [:]

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
                                .accessibilityIdentifier("ResultItem_\(index)")
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onItemClicked?(index)
                                }
                                .onHover { isHovering in
                                    if isHovering, index < results.count, selectedIndex != index {
                                        selectedIndex = index
                                    }
                                }
                                .background(
                                    GeometryReader { geometry in
                                        Color.clear.preference(
                                            key: ItemFramePreferenceKey.self,
                                            value: [index: geometry.frame(in: .named("scrollArea"))]
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
            .coordinateSpace(name: "scrollArea")
            .background(
                GeometryReader { geometry in
                    Color.clear.onAppear {
                        scrollViewHeight = geometry.size.height
                    }
                    .onChange(of: geometry.size.height) { _, newHeight in
                        scrollViewHeight = newHeight
                    }
                }
            )
            .onPreferenceChange(ItemFramePreferenceKey.self) { frames in
                itemFrames.merge(frames) { _, new in new }
            }
            .onChange(of: results.count) { _, _ in
                itemFrames.removeAll()
            }
            // Only scroll on keyboard navigation, not on hover selection.
            // Calculate target index BEFORE ViewModel updates selectedIndex.
            .onReceive(NotificationCenter.default.publisher(for: .navigateUp)) { _ in
                let targetIndex = selectedIndex - 1
                scrollToIndexIfNeeded(targetIndex, direction: .up, proxy: proxy)
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateDown)) { _ in
                let targetIndex = selectedIndex + 1
                scrollToIndexIfNeeded(targetIndex, direction: .down, proxy: proxy)
            }
        }
        .accessibilityIdentifier("ResultsListView")
    }

    /// Checks if the item is at least partially visible within the scroll view.
    /// Returns true if any part of the item is visible, false only if completely outside.
    private func isItemPartiallyVisible(_ itemFrame: CGRect) -> Bool {
        let itemTop = itemFrame.minY
        let itemBottom = itemFrame.maxY

        // In scroll view's local coordinates:
        // - Items above visible area have negative minY
        // - Items below visible area have minY > scrollViewHeight
        // Item is partially visible if it overlaps with visible area [0, scrollViewHeight]
        return itemBottom > 0 && itemTop < scrollViewHeight
    }

    private func scrollToIndexIfNeeded(_ index: Int, direction: NavigationDirection, proxy: ScrollViewProxy) {
        guard index >= 0, index < results.count else { return }
        guard let itemFrame = itemFrames[index] else { return }

        // Check if target item is at least partially visible
        guard !isItemPartiallyVisible(itemFrame) else { return }

        // Scroll with minimal movement: place item at edge of scroll direction
        let anchor: UnitPoint = direction == .down ? .bottom : .top

        withAnimation(.easeInOut(duration: 0.15)) {
            proxy.scrollTo(index, anchor: anchor)
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

/// Preference key for tracking individual item frames in scroll view's local coordinate space.
private struct ItemFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
