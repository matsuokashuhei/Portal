//
//  AccessibilityHelperTests.swift
//  PortalTests
//
//  Created by Claude Code on 2026/01/18.
//

import ApplicationServices
import Testing
@testable import Portal

struct AccessibilityHelperTests {
    private struct StubProvider: AccessibilityHelper.FocusedElementProviding {
        let focused: AXUIElement?
        let role: String?

        func focusedElement() -> AXUIElement? {
            focused
        }

        func role(for element: AXUIElement) -> String? {
            role
        }
    }

    @Test
    func testFocusedElementRoleReturnsNilWhenNoFocus() {
        let provider = StubProvider(focused: nil, role: nil)
        #expect(AccessibilityHelper.focusedElementRole(using: provider) == nil)
    }

    @Test
    func testFocusedElementRoleReturnsRole() {
        let element = AXUIElementCreateSystemWide()
        let provider = StubProvider(focused: element, role: "AXSearchField")
        #expect(AccessibilityHelper.focusedElementRole(using: provider) == "AXSearchField")
    }

    @Test
    func testIsTextInputElementFocusedTrueForTextField() {
        let element = AXUIElementCreateSystemWide()
        let provider = StubProvider(focused: element, role: "AXTextField")
        #expect(AccessibilityHelper.isTextInputElementFocused(using: provider))
    }

    @Test
    func testIsTextInputElementFocusedFalseForNonTextRole() {
        let element = AXUIElementCreateSystemWide()
        let provider = StubProvider(focused: element, role: "AXButton")
        #expect(!AccessibilityHelper.isTextInputElementFocused(using: provider))
    }
}
