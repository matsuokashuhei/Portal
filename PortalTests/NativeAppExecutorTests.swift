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

    // Helper to create a dummy Element for testing
    private func createDummyElement() -> Element {
        Element(element: AXUIElementCreateSystemWide())
    }

    // MARK: - Basic Execution Tests

    @MainActor
    @Test
    func testExecuteWithSystemWideElementReturnsSuccess() {
        // SystemWide element will still return success because execute()
        // delegates to Element.performAction which doesn't validate element type
        let executor = NativeAppExecutor()
        let element = createDummyElement()
        let target = HintTarget(element: element)

        let result = executor.execute(target)

        switch result {
        case .success:
            // Expected: execute delegates to Element.performAction
            break
        case .failure(let error):
            Issue.record("Expected success, but got error: \(error)")
        }
    }
}
