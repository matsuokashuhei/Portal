//
//  CrawlerFactory.swift
//  Portal
//
//  Created by Claude Code on 2026/01/10.
//

import AppKit

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
    /// Registered crawlers in order of priority (most specific first).
    private var crawlers: [ElementCrawler] = []

    /// The default crawler used when no specialized crawler claims the application.
    private let defaultCrawler: ElementCrawler

    /// Creates a new CrawlerFactory with the default set of crawlers.
    init() {
        self.defaultCrawler = NativeAppCrawler()
        // Register specialized crawlers in priority order
        self.crawlers.append(ElectronCrawler())
    }

    /// Creates a CrawlerFactory with custom crawlers (for testing).
    ///
    /// - Parameters:
    ///   - crawlers: Array of crawlers in priority order.
    ///   - defaultCrawler: The fallback crawler.
    init(crawlers: [ElementCrawler], defaultCrawler: ElementCrawler) {
        self.crawlers = crawlers
        self.defaultCrawler = defaultCrawler
    }

    /// Returns the appropriate crawler for the given application.
    ///
    /// The factory checks registered crawlers in order, returning the first
    /// one that claims to handle the application. If no specialized crawler
    /// handles the application, the default NativeAppCrawler is returned.
    ///
    /// - Parameter app: The application to find a crawler for.
    /// - Returns: An ElementCrawler that can handle the application.
    func crawler(for app: NSRunningApplication) -> ElementCrawler {
        // Check specialized crawlers first (in priority order)
        for crawler in crawlers {
            if crawler.canHandle(app) {
                #if DEBUG
                print("[CrawlerFactory] Using \(type(of: crawler)) for \(app.bundleIdentifier ?? "unknown")")
                #endif
                return crawler
            }
        }

        // Fall back to default crawler
        #if DEBUG
        print("[CrawlerFactory] Using default NativeAppCrawler for \(app.bundleIdentifier ?? "unknown")")
        #endif
        return defaultCrawler
    }

    /// Registers a specialized crawler.
    ///
    /// Crawlers are checked in registration order, so register more specific
    /// crawlers first.
    ///
    /// - Parameter crawler: The crawler to register.
    func register(_ crawler: ElementCrawler) {
        crawlers.append(crawler)
    }
}
