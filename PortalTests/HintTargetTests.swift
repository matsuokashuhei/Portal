//
//  HintTargetTests.swift
//  PortalTests
//
//  Created by Claude Code on 2025/12/31.
//

import ApplicationServices
import Testing
@testable import Portal

struct HintTargetTests {

    // Helper to create a dummy Element for testing
    private func createDummyElement() -> Element {
        Element(element: AXUIElementCreateSystemWide())
    }

    @Test
    func testIdMatchesElementId() {
        let element = createDummyElement()
        let target = HintTarget(element: element)

        #expect(target.id == element.id)
    }

    @Test
    func testIdIsStableForSameElement() {
        let element = createDummyElement()

        let target1 = HintTarget(element: element)
        let target2 = HintTarget(element: element)

        #expect(target1.id == target2.id)
    }

    @Test
    func testHashableConformanceUsesId() {
        let element = createDummyElement()

        let target1 = HintTarget(element: element)
        let target2 = HintTarget(element: element)

        // Same Element should yield the same identifier, so targets are equal.
        #expect(target1 == target2)

        var set: Set<HintTarget> = [target1]
        set.insert(target2)
        #expect(set.count == 1)
    }

    // MARK: - HintTargetType Tests

    @Test
    func testTargetTypeDefaultsToNative() {
        let element = createDummyElement()
        let target = HintTarget(element: element)

        #expect(target.targetType == .native)
    }
}
