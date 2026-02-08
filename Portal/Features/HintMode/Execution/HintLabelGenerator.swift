//
//  HintLabelGenerator.swift
//  Portal
//
//  Created by Claude Code on 2026/01/03.
//

import CoreGraphics
import Foundation

/// Generates Vimium-style hint labels (A-Z, AA-AZ, BA-BZ, etc.).
///
/// The generator creates sequential labels starting from single characters (A-Z),
/// then progressing to two-character combinations when more than 26 labels are needed.
enum HintLabelGenerator {
    /// The alphabet used for generating labels.
    /// Note: "F" is excluded because it's reserved for hint mode activation.
    private static let alphabet = Array("ABCDEGHIJKLMNOPQRSTUVWXYZ")

    /// Generates a label for a given index.
    ///
    /// This method is designed for progressive/streaming label generation where
    /// the total count is not known in advance. Labels are always two characters
    /// starting from AA, AB, AC, ... to avoid prefix conflicts.
    ///
    /// - Parameter index: The zero-based index of the label to generate.
    /// - Returns: The two-character label string for the given index.
    static func generateLabel(at index: Int) -> String {
        guard index >= 0 else { return "" }

        let alphabetCount = alphabet.count

        let first = index / alphabetCount
        let second = index % alphabetCount

        // Ensure we don't exceed available two-char combinations
        guard first < alphabetCount else {
            // Fallback for very large indices (unlikely in practice)
            return "Z\(index)"
        }

        return String(alphabet[first]) + String(alphabet[second])
    }

    /// Filters hint labels based on user input.
    ///
    /// - Parameters:
    ///   - hints: The original hint labels.
    ///   - input: The user's current input (case-insensitive).
    /// - Returns: Hint labels whose label starts with the input.
    static func filterHints(_ hints: [HintLabel], by input: String) -> [HintLabel] {
        guard !input.isEmpty else { return hints }
        let uppercasedInput = input.uppercased()
        return hints.filter { $0.label.hasPrefix(uppercasedInput) }
    }
}
