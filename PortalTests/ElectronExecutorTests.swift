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

    // Helper to create a dummy AXUIElement for testing
    private func createDummyElement() -> AXUIElement {
        AXUIElementCreateSystemWide()
    }

    // MARK: - Basic Execution Tests

    @MainActor
    @Test
    func testExecuteWithDisabledTargetReturnsTargetDisabled() {
        let executor = ElectronExecutor()
        let element = createDummyElement()
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let target = HintTarget(title: "Test", axElement: element, isEnabled: false, cachedFrame: frame, targetType: .electron)

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
        // Without cachedFrame, it should return elementInvalid
        let executor = ElectronExecutor()
        let element = createDummyElement()
        let target = HintTarget(title: "Test", axElement: element, isEnabled: true, targetType: .electron)

        let result = executor.execute(target)

        // SystemWide element will fail validation and no cachedFrame fallback
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
            "AXLink", "AXButton", "AXTextField", "AXTextArea", "AXCheckBox",
            "AXRadioButton", "AXMenuItem", "AXTab", "AXStaticText", "AXRow"
        ]

        for role in expectedRoles {
            #expect(ElectronExecutor.validRoles.contains(role), "Expected validRoles to contain \(role)")
        }
    }

    @Test
    func testValidRolesContainsNativeChromeRoles() {
        // Electron apps have native chrome elements (window controls, menus)
        let nativeChromeRoles = ["AXGroup", "AXCell", "AXOutlineRow"]

        for role in nativeChromeRoles {
            #expect(ElectronExecutor.validRoles.contains(role), "Expected validRoles to contain native chrome role \(role)")
        }
    }

    // MARK: - CachedFrame Tests

    @Test
    func testTargetWithCachedFrameStoresFrameCorrectly() {
        let element = createDummyElement()
        let frame = CGRect(x: 100, y: 200, width: 300, height: 400)
        let target = HintTarget(title: "Test", axElement: element, isEnabled: true, cachedFrame: frame, targetType: .electron)

        #expect(target.cachedFrame == frame)
        #expect(target.cachedFrame?.minX == 100)
        #expect(target.cachedFrame?.minY == 200)
        #expect(target.cachedFrame?.width == 300)
        #expect(target.cachedFrame?.height == 400)
    }
}
