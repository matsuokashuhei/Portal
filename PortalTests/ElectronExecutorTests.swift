//
//  ElectronExecutorTests.swift
//  PortalTests
//
//  Created by Claude Code on 2026/01/12.
//

import ApplicationServices
import Testing
@testable import Portal

struct ElectronExecutorTests {

    // MARK: - Valid Roles Tests

    @Test
    func testValidRolesContainsExpectedRoles() {
        let expectedRoles = [
            "AXLink", "AXButton", "AXTextField", "AXTextArea", "AXSearchField",
            "AXCheckBox", "AXRadioButton", "AXMenuItem", "AXMenuButton",
            "AXComboBox", "AXSwitch", "AXTab", "AXStaticText", "AXRow"
        ]

        for role in expectedRoles {
            #expect(ElectronExecutor.validRoles.contains(role), "Expected validRoles to contain \(role)")
        }
    }

    @Test
    func testValidRolesContainsNativeChromeRoles() {
        let nativeChromeRoles = ["AXGroup", "AXCell", "AXOutlineRow"]

        for role in nativeChromeRoles {
            #expect(ElectronExecutor.validRoles.contains(role), "Expected validRoles to contain native chrome role \(role)")
        }
    }
}
