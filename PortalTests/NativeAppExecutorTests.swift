//
//  NativeAppExecutorTests.swift
//  PortalTests
//
//  Created by Claude Code on 2026/01/12.
//

import ApplicationServices
import Testing
@testable import Portal

struct NativeAppExecutorTests {

    // Helper to create a dummy AXUIElement for testing
    private func createDummyElement() -> AXUIElement {
        AXUIElementCreateSystemWide()
    }

    // MARK: - Basic Execution Tests

    @MainActor
    @Test
    func testExecuteWithDisabledTargetReturnsTargetDisabled() {
        let executor = NativeAppExecutor()
        let element = createDummyElement()
        let target = HintTarget(title: "Test", axElement: element, isEnabled: false, targetType: .native)

        let result = executor.execute(target)

        switch result {
        case .failure(let error):
            #expect(error == .targetDisabled)
        case .success:
            Issue.record("Expected targetDisabled error, but got success")
        }
    }

    @MainActor
    @Test
    func testExecuteWithEnabledTargetAndSystemWideElementReturnsElementInvalid() {
        // SystemWide element is not a valid UI element for interaction
        let executor = NativeAppExecutor()
        let element = createDummyElement()
        let target = HintTarget(title: "Test", axElement: element, isEnabled: true, targetType: .native)

        let result = executor.execute(target)

        // SystemWide element will fail validation
        switch result {
        case .failure(let error):
            #expect(error == .elementInvalid)
        case .success:
            Issue.record("Expected elementInvalid error, but got success")
        }
    }

    // MARK: - Valid Roles Tests

    @Test
    func testValidRolesContainsExpectedRoles() {
        let expectedRoles = [
            "AXButton", "AXRow", "AXCell", "AXCheckBox", "AXSwitch",
            "AXTextField", "AXSlider", "AXIncrementor", "AXTab"
        ]

        for role in expectedRoles {
            #expect(NativeAppExecutor.validRoles.contains(role), "Expected validRoles to contain \(role)")
        }
    }

    @Test
    func testValidRolesDoesNotContainWebRoles() {
        // Web-specific roles should not be in native executor's valid roles
        let webRoles = ["AXWebArea", "AXMenuItemCheckbox", "AXMenuItemRadio"]

        for role in webRoles {
            #expect(!NativeAppExecutor.validRoles.contains(role), "Expected validRoles to NOT contain \(role)")
        }
    }
}
