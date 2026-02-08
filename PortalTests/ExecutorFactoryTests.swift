//
//  ExecutorFactoryTests.swift
//  PortalTests
//
//  Created by Claude Code on 2026/01/12.
//

import ApplicationServices
import Testing
@testable import Portal

struct ExecutorFactoryTests {

    // Helper to create a dummy Element for testing
    private func createDummyElement() -> Element {
        Element(element: AXUIElementCreateSystemWide())
    }

    // MARK: - Executor Selection Tests

    @MainActor
    @Test
    func testExecutorForNativeTargetReturnsNativeExecutor() {
        let factory = ExecutorFactory()
        let element = createDummyElement()
        let target = HintTarget(element: element)

        let executor = factory.executor(for: target)

        #expect(executor is NativeAppExecutor)
    }

    @MainActor
    @Test
    func testExecutorForDefaultTargetReturnsNativeExecutor() {
        let factory = ExecutorFactory()
        let element = createDummyElement()
        let target = HintTarget(element: element)

        let executor = factory.executor(for: target)

        #expect(executor is NativeAppExecutor)
    }

    // MARK: - Custom Executor Injection Tests

    @MainActor
    @Test
    func testCustomNativeExecutorIsUsed() {
        let mockNativeExecutor = MockExecutor()
        let mockElectronExecutor = MockExecutor()

        let factory = ExecutorFactory(nativeExecutor: mockNativeExecutor, electronExecutor: mockElectronExecutor)
        let element = createDummyElement()

        let nativeTarget = HintTarget(element: element)

        let nativeExecutor = factory.executor(for: nativeTarget)

        #expect(nativeExecutor is MockExecutor)
    }
}

// MARK: - Mock Executor

/// Mock executor for testing ExecutorFactory injection.
@MainActor
final class MockExecutor: ActionExecutor {
    var executedTargets: [HintTarget] = []

    func execute(_ target: HintTarget, actionName: String?) -> Result<Void, HintExecutionError> {
        executedTargets.append(target)
        return .success(())
    }
}
