//
//  ExecutorFactory.swift
//  Portal
//
//  Created by Claude Code on 2026/01/10.
//

/// Factory for creating ActionExecutor instances.
///
/// Currently, all targets use AccessibilityExecutor since all hint targets
/// are based on AXUIElement. In the future, this factory can be extended
/// to support different executor types (e.g., CDP-based execution for
/// browser elements).
///
/// ## Usage
/// ```swift
/// let factory = ExecutorFactory()
/// let executor = factory.executor()
/// let result = executor.execute(target)
/// ```
@MainActor
final class ExecutorFactory {
    /// The default executor used for all targets.
    private let defaultExecutor: ActionExecutor

    /// Creates a new ExecutorFactory with the default executor.
    init() {
        self.defaultExecutor = AccessibilityExecutor()
    }

    /// Creates an ExecutorFactory with a custom executor (for testing).
    ///
    /// - Parameter defaultExecutor: The executor to use for all targets.
    init(defaultExecutor: ActionExecutor) {
        self.defaultExecutor = defaultExecutor
    }

    /// Returns the appropriate executor for hint targets.
    ///
    /// Currently returns AccessibilityExecutor for all targets.
    /// Future versions may select different executors based on target type.
    ///
    /// - Returns: An ActionExecutor instance.
    func executor() -> ActionExecutor {
        return defaultExecutor
    }
}
