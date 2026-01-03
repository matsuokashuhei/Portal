//
//  HintOverlayView.swift
//  Portal
//
//  Created by Claude Code on 2026/01/03.
//

import SwiftUI

/// The main overlay view that displays hint labels at element positions.
///
/// This view is displayed fullscreen over the target application and shows
/// keyboard navigation hints at the position of each interactive element.
struct HintOverlayView: View {
    /// All hint labels to potentially display.
    let hints: [HintLabel]

    /// The user's current input for filtering hints.
    let currentInput: String

    /// The screen bounds for coordinate conversion.
    let screenBounds: CGRect

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Semi-transparent overlay (optional, can be removed for pure transparency)
                Color.black.opacity(0.01)
                    .allowsHitTesting(false)

                // Hint labels positioned at element locations
                ForEach(filteredHints) { hint in
                    HintLabelView(hint: hint, input: currentInput)
                        .position(
                            x: hint.frame.minX + 10,
                            y: geometry.size.height - hint.frame.maxY + 10
                        )
                }
            }
        }
    }

    /// Hints filtered by the current user input.
    private var filteredHints: [HintLabel] {
        HintLabelGenerator.filterHints(hints, by: currentInput)
    }
}

/// A single hint label badge displayed at an element's position.
struct HintLabelView: View {
    let hint: HintLabel
    let input: String

    var body: some View {
        HStack(spacing: 0) {
            // Matched portion (dimmed)
            if !input.isEmpty {
                Text(matchedPortion)
                    .foregroundColor(.white.opacity(0.6))
            }

            // Remaining portion (bright)
            Text(remainingPortion)
                .foregroundColor(.white)
        }
        .font(.system(size: 11, weight: .bold, design: .monospaced))
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.orange)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.black.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
    }

    /// The portion of the label that matches the current input.
    private var matchedPortion: String {
        guard !input.isEmpty else { return "" }
        let inputLength = min(input.count, hint.label.count)
        return String(hint.label.prefix(inputLength))
    }

    /// The portion of the label that hasn't been matched yet.
    private var remainingPortion: String {
        guard !input.isEmpty else { return hint.label }
        let inputLength = min(input.count, hint.label.count)
        return String(hint.label.dropFirst(inputLength))
    }
}

/// View showing the current input buffer at the bottom of the screen.
struct InputBufferView: View {
    let input: String

    var body: some View {
        if !input.isEmpty {
            HStack {
                Text("Input:")
                    .foregroundColor(.secondary)
                Text(input)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .shadow(radius: 4)
        }
    }
}

// MARK: - Previews

#Preview("Hint Label") {
    HintLabelView(
        hint: HintLabel(
            label: "AB",
            frame: CGRect(x: 100, y: 100, width: 80, height: 24),
            menuItem: MenuItem(
                title: "Test",
                path: ["Test"],
                keyboardShortcut: nil,
                axElement: AXUIElementCreateSystemWide(),
                isEnabled: true,
                type: .window
            )
        ),
        input: "A"
    )
    .padding()
    .background(Color.gray)
}

#Preview("Input Buffer") {
    VStack(spacing: 20) {
        InputBufferView(input: "")
        InputBufferView(input: "A")
        InputBufferView(input: "AB")
    }
    .padding()
}
