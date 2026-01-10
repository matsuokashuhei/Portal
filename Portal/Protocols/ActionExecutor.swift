//
//  ActionExecutor.swift
//  Portal
//
//  Created by Claude Code on 2026/01/10.
//

/// Protocol for executing actions on hint targets.
///
/// Implementations of this protocol are responsible for performing actions
/// on UI elements discovered by an `ElementCrawler`. Different implementations
/// can handle different types of targets (native macOS elements, web elements, etc.).
///
/// ## Thread Safety
/// All methods must be called on the main thread due to Accessibility API requirements.
@MainActor
protocol ActionExecutor {
    /// Executes an action on the specified hint target.
    ///
    /// - Parameter target: The target to execute an action on.
    /// - Returns: `.success(())` if the action was performed successfully,
    ///            `.failure(HintExecutionError)` otherwise.
    func execute(_ target: HintTarget) -> Result<Void, HintExecutionError>
}
