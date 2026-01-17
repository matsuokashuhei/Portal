//
//  ElementValidatorTests.swift
//  PortalTests
//
//  Created by Claude Code on 2026/01/18.
//

import Testing
@testable import Portal

struct ElementValidatorTests {
    @Test
    func testInvalidWhenRoleMissing() {
        let snapshot = ElementValidationSnapshot(role: nil, subrole: nil, possibleTitles: ["Title"])
        let isValid = ElementValidator.isValid(
            snapshot,
            expectedTitle: "Title",
            validRoles: ["AXButton"],
            validateTitle: true,
            titleMatchMode: .exact
        )
        #expect(!isValid)
    }

    @Test
    func testInvalidWhenRoleNotInValidRoles() {
        let snapshot = ElementValidationSnapshot(role: "AXStaticText", subrole: nil, possibleTitles: ["Title"])
        let isValid = ElementValidator.isValid(
            snapshot,
            expectedTitle: "Title",
            validRoles: ["AXButton"],
            validateTitle: true,
            titleMatchMode: .exact
        )
        #expect(!isValid)
    }

    @Test
    func testWindowControlSubroleSkipsTitleValidation() {
        let snapshot = ElementValidationSnapshot(
            role: "AXButton",
            subrole: "AXCloseButton",
            possibleTitles: []
        )
        let isValid = ElementValidator.isValid(
            snapshot,
            expectedTitle: "DoesNotMatter",
            validRoles: ["AXButton"],
            validateTitle: true,
            titleMatchMode: .exact
        )
        #expect(isValid)
    }

    @Test
    func testValidateTitleFalseSkipsTitleMatching() {
        let snapshot = ElementValidationSnapshot(role: "AXButton", subrole: nil, possibleTitles: [])
        let isValid = ElementValidator.isValid(
            snapshot,
            expectedTitle: "Expected",
            validRoles: ["AXButton"],
            validateTitle: false,
            titleMatchMode: .exact
        )
        #expect(isValid)
    }

    @Test
    func testValidateTitleTrueUsesTitleMatcher() {
        let snapshot = ElementValidationSnapshot(role: "AXButton", subrole: nil, possibleTitles: ["Other"])
        let isValid = ElementValidator.isValid(
            snapshot,
            expectedTitle: "Expected",
            validRoles: ["AXButton"],
            validateTitle: true,
            titleMatchMode: .exact
        )
        #expect(!isValid)
    }
}
