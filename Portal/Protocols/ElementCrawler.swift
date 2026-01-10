//
//  ElementCrawler.swift
//  Portal
//
//  Created by Claude Code on 2026/01/10.
//

import AppKit

/// Protocol for crawling UI elements from an application.
///
/// Implementations of this protocol are responsible for discovering actionable
/// UI elements within an application. Different implementations can handle
/// different types of applications (native macOS apps, Electron apps, etc.).
///
/// ## Thread Safety
/// All methods must be called on the main thread due to Accessibility API requirements.
@MainActor
protocol ElementCrawler {
    /// Crawls UI elements from the specified application.
    ///
    /// - Parameter app: The application to crawl elements from.
    /// - Returns: An array of discovered hint targets.
    /// - Throws: An error if crawling fails (e.g., accessibility not granted).
    func crawlElements(_ app: NSRunningApplication) async throws -> [HintTarget]

    /// Determines whether this crawler can handle the specified application.
    ///
    /// - Parameter app: The application to check.
    /// - Returns: `true` if this crawler can handle the application, `false` otherwise.
    func canHandle(_ app: NSRunningApplication) -> Bool
}
