//
//  FuzzySearch.swift
//  Portal
//
//  Created by Claude Code on 2026/01/01.
//

import Foundation

// MARK: - Unicode Normalization

private extension String {
    /// Returns the string in NFC (Canonical Decomposition, followed by Canonical Composition) form.
    /// This ensures consistent character representation for matching, handling cases like:
    /// - Composed vs decomposed Japanese dakuten (が vs か + ◌゙, U+304B + U+3099)
    /// - macOS file system NFD strings
    var nfcNormalized: String {
        (self as NSString).precomposedStringWithCanonicalMapping
    }
}

/// Performs fuzzy string matching with scoring for menu items.
///
/// The algorithm scores matches based on:
/// - Consecutive character matches (higher score)
/// - Word boundary matches (higher score)
/// - Prefix matches (higher score)
/// - Partial matches (lower score)
struct FuzzySearch {
    /// Result of a fuzzy search match.
    struct Match {
        /// The matched menu item.
        let item: MenuItem
        /// Match score (higher is better).
        let score: Int
        /// Ranges of matched characters in the item's original (non-normalized) `title` string.
        /// These ranges are string indices into `item.title`, suitable for use in UI highlighting.
        let matchedRanges: [Range<String.Index>]
    }

    // MARK: - Scoring Constants

    private enum Score {
        /// Bonus for matching at the start of a string.
        static let prefixMatch = 15
        /// Bonus for matching at a word boundary (after space, hyphen, etc.).
        static let wordBoundaryMatch = 10
        /// Bonus for each consecutive matched character.
        static let consecutiveMatch = 8
        /// Base score for each matched character.
        static let characterMatch = 1
        /// Penalty for each unmatched character between matches.
        static let unmatchedPenalty = -1
    }

    // MARK: - Public Methods

    /// Searches for items matching the query using fuzzy matching.
    ///
    /// - Parameters:
    ///   - query: The search query string.
    ///   - items: The menu items to search within.
    /// - Returns: Array of matches sorted by score (highest first), excluding non-matches.
    static func search(query: String, in items: [MenuItem]) -> [Match] {
        let normalizedQuery = query.nfcNormalized.lowercased()

        guard !normalizedQuery.isEmpty else {
            return items.map { Match(item: $0, score: 0, matchedRanges: []) }
        }

        return items.compactMap { item in
            if let (score, ranges) = calculateMatch(query: normalizedQuery, in: item.title) {
                return Match(item: item, score: score, matchedRanges: ranges)
            }
            return nil
        }
        .sorted { $0.score > $1.score }
    }

    // MARK: - Private Methods

    /// Calculates the match score and ranges for a query against a target string.
    ///
    /// - Parameters:
    ///   - query: The normalized (NFC + lowercased) search query.
    ///   - target: The string to match against.
    /// - Returns: A tuple of (score, matchedRanges) if matched, nil if no match.
    ///
    /// - Note: The String.Index operations have O(n) complexity per call. For menu item titles
    ///   (typically < 50 characters), this is negligible. If performance becomes an issue with
    ///   very long strings, consider maintaining integer offsets alongside String.Index.
    ///
    /// - Note: Unicode-safe implementation using NFC normalization. The index mapping works
    ///   correctly because Swift String indexing operates on grapheme clusters, and NFC +
    ///   lowercased() preserve grapheme cluster counts for supported languages (English,
    ///   Japanese, Chinese, Korean).
    private static func calculateMatch(
        query: String,
        in target: String
    ) -> (score: Int, ranges: [Range<String.Index>])? {
        let normalizedTarget = target.nfcNormalized.lowercased()

        var queryIndex = query.startIndex
        var targetIndex = normalizedTarget.startIndex
        var score = 0
        var matchedRanges: [Range<String.Index>] = []
        var consecutiveCount = 0
        var lastMatchIndex: String.Index?
        var currentRangeStart: String.Index?

        while queryIndex < query.endIndex && targetIndex < normalizedTarget.endIndex {
            let queryChar = query[queryIndex]
            let targetChar = normalizedTarget[targetIndex]

            if queryChar == targetChar {
                // Character matched
                score += Score.characterMatch

                // Bonus for prefix match
                if targetIndex == normalizedTarget.startIndex {
                    score += Score.prefixMatch
                }

                // Bonus for word boundary match (but avoid double bonus at string start)
                if targetIndex != normalizedTarget.startIndex &&
                    isWordBoundary(at: targetIndex, in: normalizedTarget) {
                    score += Score.wordBoundaryMatch
                }

                // Bonus for consecutive matches
                // The multiplier rewards longer consecutive runs, making
                // "Copy" rank higher than "CoOpYard" when searching for "cop".
                // Consecutive bonus only applies from the second consecutive character onward.
                if let lastIdx = lastMatchIndex,
                   normalizedTarget.index(after: lastIdx) == targetIndex {
                    consecutiveCount += 1
                    score += Score.consecutiveMatch * consecutiveCount
                } else {
                    // Starting a new sequence - no consecutive bonus for first char
                    consecutiveCount = 0
                }

                // Track matched ranges (Unicode-safe with NFC normalization)
                let originalTargetIndex = target.index(target.startIndex, offsetBy: normalizedTarget.distance(from: normalizedTarget.startIndex, to: targetIndex))

                if currentRangeStart == nil {
                    currentRangeStart = originalTargetIndex
                }

                // Check if this ends a range (next char won't match or end of query)
                let nextQueryIndex = query.index(after: queryIndex)
                let nextTargetIndex = normalizedTarget.index(after: targetIndex)
                let isLastQueryChar = nextQueryIndex == query.endIndex
                let isLastTargetChar = nextTargetIndex == normalizedTarget.endIndex
                // Safe to access: only compare when both indices are in bounds
                let nextWontMatch = !isLastQueryChar && !isLastTargetChar &&
                    query[nextQueryIndex] != normalizedTarget[nextTargetIndex]

                if isLastQueryChar || isLastTargetChar || nextWontMatch {
                    if let start = currentRangeStart {
                        let endIndex = target.index(after: originalTargetIndex)
                        matchedRanges.append(start..<endIndex)
                        currentRangeStart = nil
                    }
                }

                lastMatchIndex = targetIndex
                queryIndex = query.index(after: queryIndex)
            } else {
                // No match - apply penalty for gap
                if lastMatchIndex != nil {
                    score += Score.unmatchedPenalty
                }
            }

            targetIndex = normalizedTarget.index(after: targetIndex)
        }

        // All query characters must be matched
        guard queryIndex == query.endIndex else {
            return nil
        }

        // Close any remaining range (Unicode-safe with NFC normalization)
        if let start = currentRangeStart, let lastIdx = lastMatchIndex {
            let offset = normalizedTarget.distance(from: normalizedTarget.startIndex, to: lastIdx)
            let originalLastIndex = target.index(target.startIndex, offsetBy: offset)
            let endIndex = target.index(after: originalLastIndex)
            matchedRanges.append(start..<endIndex)
        }

        return (score, matchedRanges)
    }

    /// Determines if the given index is at a word boundary.
    ///
    /// A word boundary is defined as:
    /// - The start of the string
    /// - After a space, hyphen, underscore, or other non-alphanumeric character
    /// - A lowercase letter following an uppercase letter (camelCase boundary)
    private static func isWordBoundary(at index: String.Index, in string: String) -> Bool {
        guard index != string.startIndex else {
            return true
        }

        let prevIndex = string.index(before: index)
        let prevChar = string[prevIndex]
        let currentChar = string[index]

        // After non-alphanumeric character
        if !prevChar.isLetter && !prevChar.isNumber {
            return true
        }

        // CamelCase boundary: lowercase after uppercase
        if prevChar.isUppercase && currentChar.isLowercase {
            return true
        }

        // Transition from lowercase to uppercase
        if prevChar.isLowercase && currentChar.isUppercase {
            return true
        }

        return false
    }
}
