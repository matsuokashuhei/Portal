//
//  SearchFieldView.swift
//  Portal
//
//  Created by Claude Code on 2025/12/30.
//

import SwiftUI

struct SearchFieldView: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            TextField("Search commands...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused(isFocused)
                .accessibilityLabel("Search commands")
                .accessibilityIdentifier("SearchTextField")
        }
        .padding(12)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("SearchFieldView")
    }
}
