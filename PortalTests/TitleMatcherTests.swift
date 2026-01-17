//
//  TitleMatcherTests.swift
//  PortalTests
//
//  Created by Claude Code on 2026/01/18.
//

import Testing
@testable import Portal

struct TitleMatcherTests {
    @Test
    func testExactMatchRequiresExactCase() {
        #expect(TitleMatcher.matches(expected: "Inbox", candidates: ["Inbox"], mode: .exact))
        #expect(!TitleMatcher.matches(expected: "Inbox", candidates: ["inbox"], mode: .exact))
    }

    @Test
    func testRelaxedMatchNormalizesWhitespaceAndCase() {
        #expect(TitleMatcher.matches(expected: "  InBox  ", candidates: ["inbox"], mode: .relaxed))
        #expect(TitleMatcher.matches(expected: "In  box", candidates: ["in box"], mode: .relaxed))
    }

    @Test
    func testRelaxedMatchAllowsBoundaryPrefix() {
        #expect(TitleMatcher.matches(expected: "Inbox", candidates: ["Inbox (3)"], mode: .relaxed))
        #expect(!TitleMatcher.matches(expected: "In", candidates: ["Inbox (3)"], mode: .relaxed))
    }

    @Test
    func testRelaxedMatchAvoidsMidWordPrefix() {
        #expect(!TitleMatcher.matches(expected: "Menu", candidates: ["MenuBar"], mode: .relaxed))
    }
}
