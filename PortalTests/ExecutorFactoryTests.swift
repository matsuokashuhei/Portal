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

    // Helper to create a dummy AXUIElement for testing
    private func createDummyElement() -> AXUIElement {
        AXUIElementCreateSystemWide()
    }

    // MARK: - Executor Selection Tests

    @MainActor
    @Test
    func testExecutorForNativeTargetReturnsNativeExecutor() {
        let factory = ExecutorFactory()
        let element = createDummyElement()
        let target = HintTarget(title: "Test", axElement: element, isEnabled: true, targetType: .native)

        let executor = factory.executor(for: target)

        #expect(executor is NativeAppExecutor)
    }

    @MainActor
    @Test
    func testExecutorForElectronTargetReturnsElectronExecutor() {
        let factory = ExecutorFactory()
        let element = createDummyElement()
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let target = HintTarget(title: "Test", axElement: element, isEnabled: true, cachedFrame: frame, targetType: .electron)

        let executor = factory.executor(for: target)

        #expect(executor is ElectronExecutor)
    }

    @MainActor
    @Test
    func testExecutorForDefaultTargetReturnsNativeExecutor() {
        let factory = ExecutorFactory()
        let element = createDummyElement()
        // Default targetType is .native
        let target = HintTarget(title: "Test", axElement: element, isEnabled: true)

        let executor = factory.executor(for: target)

        #expect(executor is NativeAppExecutor)
    }

    // MARK: - Custom Executor Injection Tests

    @MainActor
    @Test
    func testCustomExecutorsAreUsed() {
        let mockNativeExecutor = MockExecutor()
        let mockElectronExecutor = MockExecutor()

        let factory = ExecutorFactory(nativeExecutor: mockNativeExecutor, electronExecutor: mockElectronExecutor)
        let element = createDummyElement()

        let nativeTarget = HintTarget(title: "Native", axElement: element, isEnabled: true, targetType: .native)
        let electronTarget = HintTarget(title: "Electron", axElement: element, isEnabled: true, targetType: .electron)

        let nativeExecutor = factory.executor(for: nativeTarget)
        let electronExecutor = factory.executor(for: electronTarget)

        #expect(nativeExecutor is MockExecutor)
        #expect(electronExecutor is MockExecutor)
    }
}

// MARK: - Mock Executor

/// Mock executor for testing ExecutorFactory injection.
@MainActor
final class MockExecutor: ActionExecutor {
    var executedTargets: [HintTarget] = []

    func execute(_ target: HintTarget) -> Result<Void, HintExecutionError> {
        executedTargets.append(target)
        return .success(())
    }
}
