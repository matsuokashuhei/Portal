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

    /// Generates an array of hint labels for the given count.
    ///
    /// - Parameter count: The number of labels to generate.
    /// - Returns: An array of label strings.
    ///
    /// All labels are two characters (AA, AB, AC, ...) to avoid prefix conflicts.
    static func generateLabels(count: Int) -> [String] {
        guard count > 0 else { return [] }

        var labels: [String] = []

        // Always use two-character labels
        outer: for first in alphabet {
            for second in alphabet {
                if labels.count >= count { break outer }
                labels.append(String(first) + String(second))
            }
        }

        return labels
    }

    /// Minimum height for hint labels when the element reports zero height.
    /// This is common in Electron apps where AXRow elements have height=0.
    private static let minimumHintHeight: CGFloat = 20.0

    /// Creates hint labels from menu items and their corresponding frames.
    ///
    /// - Parameters:
    ///   - items: The menu items to create labels for.
    ///   - frames: The screen frames for each item (must match items count).
    ///   - coordinateSystem: The coordinate system used by the frames.
    /// - Returns: An array of `HintLabel` objects.
    ///
    /// - Note: Items with `.zero` frames are filtered out as they cannot be displayed.
    ///   Items with valid position but zero height get a minimum height assigned.
    static func createHintLabels(
        from items: [HintTarget],
        frames: [CGRect],
        coordinateSystem: HintCoordinateSystem = .native
    ) -> [HintLabel] {
        // Pair items with frames and filter out completely invalid frames
        // Allow frames with zero height if they have valid position and width
        let validPairs: [(HintTarget, CGRect)] = zip(items, frames).compactMap { item, frame in
            // Completely invalid frame
            if frame == .zero {
                return nil
            }
            // Must have valid position (non-negative) and width
            guard frame.width > 0 else {
                return nil
            }
            // If height is zero or negative, assign minimum height
            if frame.height <= 0 {
                let adjustedFrame = CGRect(
                    x: frame.origin.x,
                    y: frame.origin.y,
                    width: frame.width,
                    height: minimumHintHeight
                )
                return (item, adjustedFrame)
            }
            return (item, frame)
        }

        let labels = generateLabels(count: validPairs.count)

        return zip(validPairs, labels).map { pair, label in
            HintLabel(
                label: label,
                frame: pair.1,
                target: pair.0,
                coordinateSystem: coordinateSystem
            )
        }
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

    /// Finds a unique match for the given input.
    ///
    /// - Parameters:
    ///   - hints: The hint labels to search.
    ///   - input: The user's current input.
    /// - Returns: The matching `HintLabel` if exactly one matches, otherwise nil.
    static func findUniqueMatch(in hints: [HintLabel], for input: String) -> HintLabel? {
        let filtered = filterHints(hints, by: input)
        guard filtered.count == 1 else { return nil }
        return filtered.first
    }

    /// Checks if the input exactly matches a label.
    ///
    /// - Parameters:
    ///   - hints: The hint labels to search.
    ///   - input: The user's current input.
    /// - Returns: The matching `HintLabel` if input exactly matches a label, otherwise nil.
    static func findExactMatch(in hints: [HintLabel], for input: String) -> HintLabel? {
        let uppercasedInput = input.uppercased()
        return hints.first { $0.label == uppercasedInput }
    }
}
