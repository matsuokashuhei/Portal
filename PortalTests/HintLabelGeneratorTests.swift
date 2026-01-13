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
    func testGenerateLabelsSmallCount() {
        // All labels are always two-character
        let labels = HintLabelGenerator.generateLabels(count: 5)
        #expect(labels == ["AA", "AB", "AC", "AD", "AE"])
    }

    @Test
    func testGenerateLabelsFullAlphabetRow() {
        // 25 labels (one row of two-char labels, F excluded from alphabet)
        let labels = HintLabelGenerator.generateLabels(count: 25)
        #expect(labels.count == 25)
        #expect(labels.first == "AA")
        #expect(labels.last == "AZ")
        #expect(!labels.contains("AF"))  // F should not be in the labels
    }

    @Test
    func testGenerateLabelsTwoCharacters() {
        // All labels are two-character
        let labels = HintLabelGenerator.generateLabels(count: 28)
        #expect(labels.count == 28)
        #expect(labels[0] == "AA")
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
        #expect(labels[0] == "AA")
        #expect(labels[24] == "AZ")  // 25 two-char labels starting with A (no AF)
        #expect(labels[25] == "BA")
        #expect(labels[49] == "BZ")  // 25 two-char labels starting with B (no BF)
        #expect(labels[50] == "CA")
    }

    // MARK: - Index-based Label Generation Tests (for progressive rendering)

    @Test
    func testGenerateLabelAtIndexNegative() {
        let label = HintLabelGenerator.generateLabel(at: -1)
        #expect(label == "")
    }

    @Test
    func testGenerateLabelAtIndexFirstRow() {
        // All labels are two-character, starting from AA
        // Alphabet has 25 chars (F excluded): A, B, C, D, E, G, H, ..., Z
        #expect(HintLabelGenerator.generateLabel(at: 0) == "AA")
        #expect(HintLabelGenerator.generateLabel(at: 1) == "AB")
        #expect(HintLabelGenerator.generateLabel(at: 4) == "AE")
        #expect(HintLabelGenerator.generateLabel(at: 5) == "AG")  // F is excluded
        #expect(HintLabelGenerator.generateLabel(at: 24) == "AZ") // Last of first row
    }

    @Test
    func testGenerateLabelAtIndexSecondRow() {
        // Second row starts at index 25 (BA, BB, BC, ...)
        #expect(HintLabelGenerator.generateLabel(at: 25) == "BA")
        #expect(HintLabelGenerator.generateLabel(at: 26) == "BB")
        #expect(HintLabelGenerator.generateLabel(at: 49) == "BZ")  // Last of second row
        #expect(HintLabelGenerator.generateLabel(at: 50) == "CA")  // Start of third row
        #expect(HintLabelGenerator.generateLabel(at: 74) == "CZ")  // Last of third row
        #expect(HintLabelGenerator.generateLabel(at: 75) == "DA")  // Start of fourth row
    }

    @Test
    func testGenerateLabelAtIndexSequence() {
        // Test that progressive generation produces expected sequence
        var labels: [String] = []
        for i in 0..<30 {
            labels.append(HintLabelGenerator.generateLabel(at: i))
        }
        // All labels should be two-char starting from AA
        #expect(labels[0] == "AA")
        #expect(labels[1] == "AB")
        #expect(labels[24] == "AZ")
        #expect(labels[25] == "BA")
        #expect(labels[26] == "BB")
        #expect(labels[27] == "BC")
        #expect(labels[28] == "BD")
        #expect(labels[29] == "BE")
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
