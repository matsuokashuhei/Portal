//
//  ExecutorFactory.swift
//  Portal
//
//  Created by Claude Code on 2026/01/10.
//

/// Factory for creating ActionExecutor instances based on target type.
///
/// This factory selects the appropriate executor based on `HintTargetType`:
/// - `.native`: Uses `NativeAppExecutor` for standard macOS apps
/// - `.electron`: Uses `ElectronExecutor` for Electron-based apps
///
/// ## Usage
/// ```swift
/// let factory = ExecutorFactory()
/// let executor = factory.executor(for: target)
/// let result = executor.execute(target)
/// ```
@MainActor
final class ExecutorFactory {
    /// Executor for native macOS applications.
    private let nativeExecutor: ActionExecutor

    /// Executor for Electron-based applications.
    private let electronExecutor: ActionExecutor

    /// Creates a new ExecutorFactory with default executors.
    init() {
        self.nativeExecutor = NativeAppExecutor()
        self.electronExecutor = ElectronExecutor()
    }

    /// Creates an ExecutorFactory with custom executors (for testing).
    ///
    /// - Parameters:
    ///   - nativeExecutor: The executor to use for native app targets.
    ///   - electronExecutor: The executor to use for Electron app targets.
    init(nativeExecutor: ActionExecutor, electronExecutor: ActionExecutor) {
        self.nativeExecutor = nativeExecutor
        self.electronExecutor = electronExecutor
    }

    /// Returns the appropriate executor for the given hint target.
    ///
    /// Selects executor based on `target.targetType`:
    /// - `.native`: Returns `NativeAppExecutor`
    /// - `.electron`: Returns `ElectronExecutor`
    ///
    /// - Parameter target: The hint target to get an executor for.
    /// - Returns: An ActionExecutor instance appropriate for the target type.
    func executor(for target: HintTarget) -> ActionExecutor {
        switch target.targetType {
        case .native:
            return nativeExecutor
        case .electron:
            return electronExecutor
        }
    }

    /// Returns the native executor.
    ///
    /// - Note: Prefer using `executor(for:)` to automatically select the correct executor.
    ///
    /// - Returns: The native app executor.
    @available(*, deprecated, message: "Use executor(for:) instead")
    func executor() -> ActionExecutor {
        return nativeExecutor
    }
}
