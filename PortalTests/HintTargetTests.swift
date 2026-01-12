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

    // Helper to create a dummy AXUIElement for testing
    private func createDummyElement() -> AXUIElement {
        AXUIElementCreateSystemWide()
    }

    @Test
    func testIdIsUUID() {
        let element = createDummyElement()
        let target = HintTarget(title: "Test", axElement: element, isEnabled: true)

        // ID should be a valid UUID string (36 characters with hyphens)
        #expect(target.id.count == 36)
        #expect(UUID(uuidString: target.id) != nil)
    }

    @Test
    func testIdUniqueness() {
        let element = createDummyElement()

        let target1 = HintTarget(title: "Same", axElement: element, isEnabled: true)
        let target2 = HintTarget(title: "Same", axElement: element, isEnabled: true)

        #expect(target1.id != target2.id)
    }

    @Test
    func testHashableConformanceUsesId() {
        let element = createDummyElement()

        let target1 = HintTarget(title: "Same", axElement: element, isEnabled: true)
        let target2 = HintTarget(title: "Same", axElement: element, isEnabled: true)

        // Each HintTarget has a unique UUID, so they are NOT equal even with same title/element.
        #expect(target1 != target2)

        var set: Set<HintTarget> = [target1]
        set.insert(target2)
        #expect(set.count == 2)
    }

    // MARK: - HintTargetType Tests

    @Test
    func testTargetTypeDefaultsToNative() {
        let element = createDummyElement()
        let target = HintTarget(title: "Test", axElement: element, isEnabled: true)

        #expect(target.targetType == .native)
    }

    @Test
    func testTargetTypeNativeIsSetCorrectly() {
        let element = createDummyElement()
        let target = HintTarget(title: "Test", axElement: element, isEnabled: true, targetType: .native)

        #expect(target.targetType == .native)
    }

    @Test
    func testTargetTypeElectronIsSetCorrectly() {
        let element = createDummyElement()
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let target = HintTarget(title: "Test", axElement: element, isEnabled: true, cachedFrame: frame, targetType: .electron)

        #expect(target.targetType == .electron)
        #expect(target.cachedFrame == frame)
    }
}
