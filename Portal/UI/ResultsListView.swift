//
//  ResultsListView.swift
//  Portal
//
//  Created by Claude Code on 2025/12/30.
//

import SwiftUI

struct ResultsListView: View {
    var results: [MenuItem]
    var selectedIndex: Int

    var body: some View {
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
                            .accessibilityLabel(
                                "\(item.title), \(item.pathString), Result \(index + 1) of \(results.count)\(isSelected ? ", selected" : "")"
                            )
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        }
        .accessibilityIdentifier("ResultsListView")
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

                Text(item.pathString)
                    .font(.caption)
                    .foregroundColor(.secondary)
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
