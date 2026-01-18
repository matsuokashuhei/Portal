//
//  CrawlerFactory.swift
//  Portal
//
//  Created by Claude Code on 2026/01/10.
//

import AppKit
import Logging

private let logger = PortalLogger.make("Portal", category: "CrawlerFactory")

/// Factory for creating appropriate ElementCrawler instances based on application type.
///
/// This factory implements the strategy pattern, selecting the most appropriate
/// crawler for a given application. Crawlers are checked in order of specificity,
/// with more specialized crawlers (like ElectronCrawler) taking precedence over
/// the general-purpose NativeAppCrawler.
///
/// ## Usage
/// ```swift
/// let factory = CrawlerFactory()
/// let crawler = factory.crawler(for: app)
/// let elements = try await crawler.crawlElements(app)
/// ```
@MainActor
final class CrawlerFactory {
    /// Returns the appropriate crawler for the given application.
    ///
    /// The factory checks registered crawlers in order, returning the first
    /// one that claims to handle the application. If no specialized crawler
    /// handles the application, the default NativeAppCrawler is returned.
    ///
    /// - Parameter app: The application to find a crawler for.
    /// - Returns: An ElementCrawler that can handle the application.
    static func crawler(for app: NSRunningApplication) -> ElementCrawler {
        if ElectronAppDetector().isElectronApp(app) {
            return ElectronCrawler()
        } else {
            return NativeAppCrawler()
        }
    }
}
