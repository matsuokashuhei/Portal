//
//  CrawlConfiguration.swift
//  Portal
//
//  Created by Claude Code on 2026/01/13.
//

import Foundation

/// Configuration for UI element crawling behavior.
struct CrawlConfiguration: Equatable {
    /// Maximum depth for recursive element traversal.
    let maxDepth: Int

    /// Default maximum depth.
    static let defaultMaxDepth = 15

    /// Minimum allowed depth.
    static let minDepth = 5

    /// Maximum allowed depth.
    static let maxDepthLimit = 50

    /// Default configuration.
    static let `default` = CrawlConfiguration(maxDepth: defaultMaxDepth)

    /// Loads configuration from UserDefaults.
    /// - Parameter defaults: UserDefaults instance to read from. Defaults to `.standard`.
    /// - Returns: Configuration with values from UserDefaults, clamped to valid range.
    static func load(from defaults: UserDefaults = .standard) -> CrawlConfiguration {
        let depth = defaults.integer(forKey: SettingsKey.maxCrawlDepth)
        // 0 means not set (UserDefaults returns 0 for unset integers), use default
        let validDepth = depth == 0 ? defaultMaxDepth : min(max(depth, minDepth), maxDepthLimit)
        return CrawlConfiguration(maxDepth: validDepth)
    }

    /// Saves configuration to UserDefaults.
    /// - Parameter defaults: UserDefaults instance to write to. Defaults to `.standard`.
    func save(to defaults: UserDefaults = .standard) {
        defaults.set(maxDepth, forKey: SettingsKey.maxCrawlDepth)
    }
}
