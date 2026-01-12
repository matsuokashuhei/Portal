//
//  HintTargetType.swift
//  Portal
//
//  Created by Claude Code on 2026/01/12.
//

/// Represents the type of application that a hint target belongs to.
///
/// This type is used by `ExecutorFactory` to select the appropriate executor
/// for handling the target. Different application types may require different
/// execution strategies (e.g., native Accessibility API vs mouse click fallback).
enum HintTargetType: Equatable, Sendable {
    /// Native macOS application using standard Accessibility API.
    /// These applications have stable AXUIElement references and respond
    /// well to AXPress, AXSelect, and other standard accessibility actions.
    case native

    /// Electron-based application (Slack, VS Code, Discord, etc.).
    /// These applications may have unstable AXUIElement references due to
    /// DOM updates. Mouse click fallback using cached frames is often required.
    case electron
}
