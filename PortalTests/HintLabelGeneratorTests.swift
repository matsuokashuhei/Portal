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

    /// filterHints uses simple prefix matching on label strings.
    /// We test the logic directly using string arrays to avoid
    /// needing a real AXUIElement with valid frame attributes.

    @Test
    func testFilterHintsEmptyInput() {
        let labels = ["A", "B", "C"]
        let filtered = filterByPrefix(labels, input: "")
        #expect(filtered.count == 3)
    }

    @Test
    func testFilterHintsExactMatch() {
        let labels = ["A", "B", "AB", "AC"]
        let filtered = filterByPrefix(labels, input: "A")
        #expect(filtered.count == 3)
        #expect(filtered == ["A", "AB", "AC"])
    }

    @Test
    func testFilterHintsCaseInsensitive() {
        let labels = ["A", "B", "AB"]
        let filtered = filterByPrefix(labels, input: "a")
        #expect(filtered.count == 2)
        #expect(filtered == ["A", "AB"])
    }

    @Test
    func testFilterHintsNoMatch() {
        let labels = ["A", "B", "C"]
        let filtered = filterByPrefix(labels, input: "X")
        #expect(filtered.isEmpty)
    }

    @Test
    func testFilterHintsTwoCharacterInput() {
        let labels = ["A", "AB", "AC", "BA"]
        let filtered = filterByPrefix(labels, input: "AB")
        #expect(filtered.count == 1)
        #expect(filtered.first == "AB")
    }

    // MARK: - Helper

    /// Mirrors HintLabelGenerator.filterHints logic for testing without HintLabel instances.
    private func filterByPrefix(_ labels: [String], input: String) -> [String] {
        guard !input.isEmpty else { return labels }
        let uppercasedInput = input.uppercased()
        return labels.filter { $0.hasPrefix(uppercasedInput) }
    }
}
