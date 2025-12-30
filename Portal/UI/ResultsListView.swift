//
//  ResultsListView.swift
//  Portal
//
//  Created by Claude Code on 2025/12/30.
//

import SwiftUI

struct ResultsListView: View {
    var results: [String]
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
                        let isSelected = results.indices.contains(selectedIndex) && index == selectedIndex
                        Text(results[index])
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(
                                isSelected
                                    ? Color.accentColor.opacity(0.1)
                                    : Color.clear
                            )
                            .accessibilityLabel(
                                "\(results[index]), Result \(index + 1) of \(results.count)\(isSelected ? ", selected" : "")"
                            )
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        }
        .accessibilityIdentifier("ResultsListView")
    }
}
