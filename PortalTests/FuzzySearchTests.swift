//
//  FuzzySearchTests.swift
//  PortalTests
//
//  Created by Claude Code on 2026/01/01.
//

import ApplicationServices
import Testing
@testable import Portal

struct FuzzySearchTests {

    // MARK: - Test Helpers

    /// Creates a MenuItem for testing purposes.
    private func makeMenuItem(title: String, path: [String]? = nil) -> MenuItem {
        let dummyElement = AXUIElementCreateSystemWide()
        return MenuItem(
            title: title,
            path: path ?? [title],
            keyboardShortcut: nil,
            axElement: dummyElement,
            isEnabled: true
        )
    }

    // MARK: - Empty Query Tests

    @Test
    func testEmptyQueryReturnsAllItems() {
        let items = [
            makeMenuItem(title: "Copy"),
            makeMenuItem(title: "Paste"),
            makeMenuItem(title: "Cut")
        ]

        let results = FuzzySearch.search(query: "", in: items)

        #expect(results.count == 3)
    }

    @Test
    func testEmptyQueryReturnsItemsWithZeroScore() {
        let items = [makeMenuItem(title: "Copy")]

        let results = FuzzySearch.search(query: "", in: items)

        #expect(results.first?.score == 0)
    }

    // MARK: - Basic Matching Tests

    @Test
    func testExactMatchReturnsItem() {
        let items = [
            makeMenuItem(title: "Copy"),
            makeMenuItem(title: "Paste"),
            makeMenuItem(title: "Cut")
        ]

        let results = FuzzySearch.search(query: "Copy", in: items)

        #expect(results.count == 1)
        #expect(results.first?.item.title == "Copy")
    }

    @Test
    func testPartialMatchReturnsItem() {
        let items = [
            makeMenuItem(title: "Copy"),
            makeMenuItem(title: "Paste")
        ]

        let results = FuzzySearch.search(query: "Cop", in: items)

        #expect(results.count == 1)
        #expect(results.first?.item.title == "Copy")
    }

    @Test
    func testCaseInsensitiveMatch() {
        let items = [makeMenuItem(title: "Copy")]

        let results = FuzzySearch.search(query: "copy", in: items)

        #expect(results.count == 1)
        #expect(results.first?.item.title == "Copy")
    }

    @Test
    func testNoMatchReturnsEmpty() {
        let items = [
            makeMenuItem(title: "Copy"),
            makeMenuItem(title: "Paste")
        ]

        let results = FuzzySearch.search(query: "xyz", in: items)

        #expect(results.isEmpty)
    }

    // MARK: - Fuzzy Matching Tests

    @Test
    func testFuzzyMatchWithSkippedCharacters() {
        let items = [makeMenuItem(title: "Find and Replace")]

        let results = FuzzySearch.search(query: "far", in: items)

        #expect(results.count == 1)
        #expect(results.first?.item.title == "Find and Replace")
    }

    @Test
    func testFuzzyMatchAcrossWords() {
        let items = [makeMenuItem(title: "Show All Windows")]

        let results = FuzzySearch.search(query: "saw", in: items)

        #expect(results.count == 1)
    }

    // MARK: - Scoring Tests

    @Test
    func testPrefixMatchScoresHigher() {
        let items = [
            makeMenuItem(title: "Paste"),
            makeMenuItem(title: "Copy and Paste")
        ]

        let results = FuzzySearch.search(query: "pas", in: items)

        #expect(results.count == 2)
        #expect(results.first?.item.title == "Paste")
    }

    @Test
    func testConsecutiveMatchScoresHigher() {
        let items = [
            makeMenuItem(title: "Copy"),
            makeMenuItem(title: "CoOpYard")
        ]

        let results = FuzzySearch.search(query: "cop", in: items)

        #expect(results.count == 2)
        #expect(results.first?.item.title == "Copy")
    }

    @Test
    func testWordBoundaryMatchScoresHigher() {
        let items = [
            makeMenuItem(title: "Export Settings"),
            makeMenuItem(title: "Settings")
        ]

        let results = FuzzySearch.search(query: "set", in: items)

        #expect(results.count == 2)
        // "Settings" should score higher due to prefix match
        #expect(results.first?.item.title == "Settings")
    }

    // MARK: - Matched Ranges Tests

    @Test
    func testMatchedRangesAreCorrect() {
        let items = [makeMenuItem(title: "Copy")]

        let results = FuzzySearch.search(query: "copy", in: items)

        #expect(results.first?.matchedRanges.count == 1)
        if let match = results.first, let range = match.matchedRanges.first {
            let matchedText = String(match.item.title[range])
            #expect(matchedText == "Copy")
        }
    }

    @Test
    func testMultipleMatchedRanges() {
        let items = [makeMenuItem(title: "Find and Replace")]

        let results = FuzzySearch.search(query: "far", in: items)

        // Should have three separate matched ranges for "F", "a", and "R"
        #expect(results.count == 1)
        if let match = results.first {
            let ranges = match.matchedRanges
            #expect(ranges.count == 3)

            let title = match.item.title
            let matchedTexts = ranges.map { String(title[$0]) }
            #expect(matchedTexts == ["F", "a", "R"])
        }
    }

    // MARK: - Edge Cases

    @Test
    func testEmptyItemsReturnsEmpty() {
        let items: [MenuItem] = []

        let results = FuzzySearch.search(query: "test", in: items)

        #expect(results.isEmpty)
    }

    @Test
    func testSingleCharacterQuery() {
        let items = [
            makeMenuItem(title: "Copy"),
            makeMenuItem(title: "Paste"),
            makeMenuItem(title: "Cut")
        ]

        let results = FuzzySearch.search(query: "c", in: items)

        #expect(results.count == 2) // "Copy" and "Cut"
    }

    @Test
    func testQueryLongerThanTitle() {
        let items = [makeMenuItem(title: "Cut")]

        let results = FuzzySearch.search(query: "cutting", in: items)

        #expect(results.isEmpty)
    }

    // MARK: - Sorting Tests

    @Test
    func testResultsSortedByScoreDescending() {
        let items = [
            makeMenuItem(title: "ZZZ Paste Here"),
            makeMenuItem(title: "Paste"),
            makeMenuItem(title: "AAA Paste There")
        ]

        let results = FuzzySearch.search(query: "paste", in: items)

        #expect(results.count == 3)
        // "Paste" should be first due to prefix match
        #expect(results.first?.item.title == "Paste")
    }

    // MARK: - Unicode and CJK Tests

    @Test
    func testJapaneseExactMatch() {
        let items = [makeMenuItem(title: "コピー")]

        let results = FuzzySearch.search(query: "コピー", in: items)

        #expect(results.count == 1)
        #expect(results.first?.item.title == "コピー")
    }

    @Test
    func testJapanesePartialMatch() {
        let items = [makeMenuItem(title: "ファイルを開く")]

        let results = FuzzySearch.search(query: "ファイル", in: items)

        #expect(results.count == 1)
        if let match = results.first, let range = match.matchedRanges.first {
            let matchedText = String(match.item.title[range])
            #expect(matchedText == "ファイル")
        }
    }

    @Test
    func testJapaneseFuzzyMatch() {
        let items = [makeMenuItem(title: "新規作成")]

        let results = FuzzySearch.search(query: "新作", in: items)

        #expect(results.count == 1)
        if let match = results.first {
            // "新" and "作" as separate ranges
            #expect(match.matchedRanges.count == 2)
        }
    }

    @Test
    func testChineseExactMatch() {
        let items = [makeMenuItem(title: "打开文件")]

        let results = FuzzySearch.search(query: "文件", in: items)

        #expect(results.count == 1)
    }

    @Test
    func testKoreanExactMatch() {
        let items = [makeMenuItem(title: "파일열기")]

        let results = FuzzySearch.search(query: "파일", in: items)

        #expect(results.count == 1)
    }

    @Test
    func testMixedLanguageMatch() {
        let items = [
            makeMenuItem(title: "File Open"),
            makeMenuItem(title: "ファイルを開く"),
            makeMenuItem(title: "打开文件")
        ]

        let englishResults = FuzzySearch.search(query: "file", in: items)
        #expect(englishResults.count == 1)
        #expect(englishResults.first?.item.title == "File Open")

        let japaneseResults = FuzzySearch.search(query: "ファイル", in: items)
        #expect(japaneseResults.count == 1)
        #expect(japaneseResults.first?.item.title == "ファイルを開く")
    }

    @Test
    func testJapaneseMatchedRangesCorrect() {
        let items = [makeMenuItem(title: "新規作成")]

        let results = FuzzySearch.search(query: "新規", in: items)

        #expect(results.count == 1)
        if let match = results.first, let range = match.matchedRanges.first {
            let matchedText = String(match.item.title[range])
            #expect(matchedText == "新規")
        }
    }

    @Test
    func testUnicodeNormalizationNFDInput() {
        // NFD representation: か + combining dakuten = が
        let nfdTitle = "か\u{3099}を開く"  // "がを開く" in NFD
        let items = [makeMenuItem(title: nfdTitle)]

        // NFC query
        let results = FuzzySearch.search(query: "が", in: items)

        #expect(results.count == 1)
    }
}
