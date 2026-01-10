//
//  HintLabelGeneratorTests.swift
//  PortalTests
//
//  Created by Claude Code on 2026/01/03.
//

import ApplicationServices
import CoreGraphics
import Testing
@testable import Portal

struct HintLabelGeneratorTests {

    // MARK: - Label Generation Tests

    @Test
    func testGenerateLabelsEmpty() {
        let labels = HintLabelGenerator.generateLabels(count: 0)
        #expect(labels.isEmpty)
    }

    @Test
    func testGenerateLabelsNegative() {
        let labels = HintLabelGenerator.generateLabels(count: -5)
        #expect(labels.isEmpty)
    }

    @Test
    func testGenerateLabelsSingleCharacter() {
        let labels = HintLabelGenerator.generateLabels(count: 5)
        #expect(labels == ["A", "B", "C", "D", "E"])
    }

    @Test
    func testGenerateLabelsFullAlphabet() {
        // Note: "F" is excluded from the alphabet, so we have 25 single-character labels
        let labels = HintLabelGenerator.generateLabels(count: 25)
        #expect(labels.count == 25)
        #expect(labels.first == "A")
        #expect(labels.last == "Z")
        #expect(!labels.contains("F"))  // F should not be in the labels
    }

    @Test
    func testGenerateLabelsTwoCharacters() {
        // When count > 25, ALL labels are two-character (no overlap with single-char)
        let labels = HintLabelGenerator.generateLabels(count: 28)
        #expect(labels.count == 28)
        #expect(labels[0] == "AA")  // Starts with two-char
        #expect(labels[1] == "AB")
        #expect(labels[24] == "AZ")  // 25 labels from AA to AZ (no AF)
        #expect(labels[25] == "BA")
        #expect(labels[26] == "BB")
        #expect(labels[27] == "BC")
    }

    @Test
    func testGenerateLabelsLargeCount() {
        let labels = HintLabelGenerator.generateLabels(count: 100)
        #expect(labels.count == 100)
        // When count > 25, ALL labels are two-character
        #expect(labels[0] == "AA")
        #expect(labels[24] == "AZ")  // 25 two-char labels starting with A (no AF)
        #expect(labels[25] == "BA")
        #expect(labels[49] == "BZ")  // 25 two-char labels starting with B (no BF)
        #expect(labels[50] == "CA")
    }

    // MARK: - Filter Tests

    @Test
    func testFilterHintsEmptyInput() {
        let hints = createTestHints(["A", "B", "C"])
        let filtered = HintLabelGenerator.filterHints(hints, by: "")
        #expect(filtered.count == 3)
    }

    @Test
    func testFilterHintsExactMatch() {
        let hints = createTestHints(["A", "B", "AB", "AC"])
        let filtered = HintLabelGenerator.filterHints(hints, by: "A")
        #expect(filtered.count == 3)
        #expect(filtered.map { $0.label } == ["A", "AB", "AC"])
    }

    @Test
    func testFilterHintsCaseInsensitive() {
        let hints = createTestHints(["A", "B", "AB"])
        let filtered = HintLabelGenerator.filterHints(hints, by: "a")
        #expect(filtered.count == 2)
        #expect(filtered.map { $0.label } == ["A", "AB"])
    }

    @Test
    func testFilterHintsNoMatch() {
        let hints = createTestHints(["A", "B", "C"])
        let filtered = HintLabelGenerator.filterHints(hints, by: "X")
        #expect(filtered.isEmpty)
    }

    @Test
    func testFilterHintsTwoCharacterInput() {
        let hints = createTestHints(["A", "AB", "AC", "BA"])
        let filtered = HintLabelGenerator.filterHints(hints, by: "AB")
        #expect(filtered.count == 1)
        #expect(filtered.first?.label == "AB")
    }

    // MARK: - Unique Match Tests

    @Test
    func testFindUniqueMatchSingle() {
        let hints = createTestHints(["A", "B", "C"])
        let match = HintLabelGenerator.findUniqueMatch(in: hints, for: "A")
        #expect(match?.label == "A")
    }

    @Test
    func testFindUniqueMatchMultipleCandidates() {
        let hints = createTestHints(["A", "AB", "AC"])
        let match = HintLabelGenerator.findUniqueMatch(in: hints, for: "A")
        #expect(match == nil)
    }

    @Test
    func testFindUniqueMatchNoMatch() {
        let hints = createTestHints(["A", "B", "C"])
        let match = HintLabelGenerator.findUniqueMatch(in: hints, for: "X")
        #expect(match == nil)
    }

    // MARK: - Exact Match Tests

    @Test
    func testFindExactMatchFound() {
        let hints = createTestHints(["A", "AB", "ABC"])
        let match = HintLabelGenerator.findExactMatch(in: hints, for: "AB")
        #expect(match?.label == "AB")
    }

    @Test
    func testFindExactMatchCaseInsensitive() {
        let hints = createTestHints(["AB"])
        let match = HintLabelGenerator.findExactMatch(in: hints, for: "ab")
        #expect(match?.label == "AB")
    }

    @Test
    func testFindExactMatchNotFound() {
        let hints = createTestHints(["A", "AB", "ABC"])
        let match = HintLabelGenerator.findExactMatch(in: hints, for: "AC")
        #expect(match == nil)
    }

    // MARK: - Helper

    private func createTestHints(_ labels: [String]) -> [HintLabel] {
        let dummyElement = AXUIElementCreateSystemWide()
        return labels.enumerated().map { index, label in
            let target = HintTarget(
                title: "Test \(label)",
                axElement: dummyElement,
                isEnabled: true
            )
            return HintLabel(
                label: label,
                frame: CGRect(x: CGFloat(index * 100), y: 0, width: 100, height: 20),
                target: target,
                coordinateSystem: .native
            )
        }
    }
}
