//
//  ScrollConfigurationTests.swift
//  PortalTests
//
//  Created by Claude Code on 2026/01/11.
//

import Testing
@testable import Portal

struct ScrollConfigurationTests {

    // MARK: - ScrollKey Tests

    @Test
    func testScrollKeyKeyCodes() {
        #expect(ScrollKey.h.keyCode == 4)
        #expect(ScrollKey.j.keyCode == 38)
        #expect(ScrollKey.k.keyCode == 40)
        #expect(ScrollKey.l.keyCode == 37)
    }

    @Test
    func testScrollKeyRawValues() {
        #expect(ScrollKey.h.rawValue == "h")
        #expect(ScrollKey.j.rawValue == "j")
        #expect(ScrollKey.k.rawValue == "k")
        #expect(ScrollKey.l.rawValue == "l")
    }

    @Test
    func testScrollKeyCaseIterable() {
        let allCases = ScrollKey.allCases

        #expect(allCases.count == 4)
        #expect(allCases.contains(.h))
        #expect(allCases.contains(.j))
        #expect(allCases.contains(.k))
        #expect(allCases.contains(.l))
    }

    @Test
    func testScrollKeyFromKeyCode() {
        #expect(ScrollKey.from(keyCode: 4) == .h)
        #expect(ScrollKey.from(keyCode: 38) == .j)
        #expect(ScrollKey.from(keyCode: 40) == .k)
        #expect(ScrollKey.from(keyCode: 37) == .l)
    }

    @Test
    func testScrollKeyFromInvalidKeyCode() {
        #expect(ScrollKey.from(keyCode: 0) == nil)
        #expect(ScrollKey.from(keyCode: 5) == nil)  // g key is no longer a scroll key
        #expect(ScrollKey.from(keyCode: 100) == nil)
        #expect(ScrollKey.from(keyCode: -1) == nil)
    }

    // MARK: - ScrollConfiguration Tests

    @Test
    func testScrollAmount() {
        // Scroll amount should be a reasonable value for noticeable scrolling
        #expect(ScrollConfiguration.scrollAmount > 0)
        #expect(ScrollConfiguration.scrollAmount == 60)
    }

    @Test
    func testTextInputRoles() {
        let roles = ScrollConfiguration.textInputRoles

        #expect(roles.contains("AXTextField"))
        #expect(roles.contains("AXTextArea"))
        #expect(roles.contains("AXComboBox"))
        #expect(roles.contains("AXSearchField"))
        #expect(roles.count == 4)
    }

    // MARK: - ScrollDirection Tests

    @Test
    func testScrollDirectionCases() {
        // Verify all expected cases exist
        let directions: [ScrollDirection] = [.up, .down, .left, .right]
        #expect(directions.count == 4)
    }
}
