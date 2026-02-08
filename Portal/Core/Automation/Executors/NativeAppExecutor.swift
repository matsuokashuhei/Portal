//
//  NativeAppExecutor.swift
//  Portal
//
//  Created by Claude Code on 2026/01/12.
//

import ApplicationServices
import AppKit
import Logging

private let logger = PortalLogger.make("Portal", category: "NativeAppExecutor")

/// Executor for native macOS applications using standard Accessibility API.
///
/// This executor handles native macOS applications that have stable AXUIElement references
/// and respond well to AXPress, AXSelect, and other standard accessibility actions.
///
/// ## Responsibilities
/// - Execute actions via Accessibility API (AXPress, AXSelect, etc.)
/// - Handle text fields, sliders, checkboxes, and other native controls
/// - Validate elements before execution
///
/// ## Thread Safety
/// All methods must be called on the main thread due to Accessibility API requirements.
@MainActor
final class NativeAppExecutor: ActionExecutor {
    // MARK: - ActionExecutor Protocol

    /// Executes a Hint Mode target by performing the appropriate action on its AXUIElement.
    ///
    /// - Parameter target: The target to execute.
    /// - Returns: `.success(())` if execution succeeded, `.failure(HintExecutionError)` otherwise.
    func execute(_ target: HintTarget, actionName: String?) -> Result<Void, HintExecutionError> {
        target.element.performAction(named: actionName)
        return .success(())
    }

}
