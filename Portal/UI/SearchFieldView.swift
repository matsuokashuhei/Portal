//
//  SearchFieldView.swift
//  Portal
//
//  Created by Claude Code on 2025/12/30.
//

import AppKit
import SwiftUI

struct SearchFieldView: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            FocusableTextField(
                text: $text,
                placeholder: "Search commands...",
                font: NSFont.preferredFont(forTextStyle: .title2)
            )
            .accessibilityLabel("Search commands")
            .accessibilityIdentifier("SearchTextField")
        }
        .padding(12)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("SearchFieldView")
    }
}
