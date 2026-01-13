//
//  CrawlConfigurationTests.swift
//  PortalTests
//
//  Created by Claude Code on 2026/01/13.
//

import Foundation
import Testing
@testable import Portal

struct CrawlConfigurationTests {
    @Test func defaultConfiguration() {
        let config = CrawlConfiguration.default
        #expect(config.maxDepth == 15)
    }

    @Test func defaultConstants() {
        #expect(CrawlConfiguration.defaultMaxDepth == 15)
        #expect(CrawlConfiguration.minDepth == 5)
        #expect(CrawlConfiguration.maxDepthLimit == 50)
    }

    @Test func loadDefaultWhenNotSet() {
        let defaults = UserDefaults(suiteName: "test.crawl.notset")!
        defaults.removePersistentDomain(forName: "test.crawl.notset")

        let config = CrawlConfiguration.load(from: defaults)
        #expect(config.maxDepth == CrawlConfiguration.defaultMaxDepth)
    }

    @Test func saveAndLoad() {
        let defaults = UserDefaults(suiteName: "test.crawl.saveload")!
        defaults.removePersistentDomain(forName: "test.crawl.saveload")

        let config = CrawlConfiguration(maxDepth: 25)
        config.save(to: defaults)

        let loaded = CrawlConfiguration.load(from: defaults)
        #expect(loaded.maxDepth == 25)
    }

    @Test func clampsToMinimum() {
        let defaults = UserDefaults(suiteName: "test.crawl.min")!
        defaults.removePersistentDomain(forName: "test.crawl.min")
        defaults.set(2, forKey: SettingsKey.maxCrawlDepth)

        let config = CrawlConfiguration.load(from: defaults)
        #expect(config.maxDepth == CrawlConfiguration.minDepth)
    }

    @Test func clampsToMaximum() {
        let defaults = UserDefaults(suiteName: "test.crawl.max")!
        defaults.removePersistentDomain(forName: "test.crawl.max")
        defaults.set(100, forKey: SettingsKey.maxCrawlDepth)

        let config = CrawlConfiguration.load(from: defaults)
        #expect(config.maxDepth == CrawlConfiguration.maxDepthLimit)
    }

    @Test func acceptsValueInRange() {
        let defaults = UserDefaults(suiteName: "test.crawl.inrange")!
        defaults.removePersistentDomain(forName: "test.crawl.inrange")
        defaults.set(20, forKey: SettingsKey.maxCrawlDepth)

        let config = CrawlConfiguration.load(from: defaults)
        #expect(config.maxDepth == 20)
    }

    @Test func acceptsMinBoundary() {
        let defaults = UserDefaults(suiteName: "test.crawl.minboundary")!
        defaults.removePersistentDomain(forName: "test.crawl.minboundary")
        defaults.set(CrawlConfiguration.minDepth, forKey: SettingsKey.maxCrawlDepth)

        let config = CrawlConfiguration.load(from: defaults)
        #expect(config.maxDepth == CrawlConfiguration.minDepth)
    }

    @Test func acceptsMaxBoundary() {
        let defaults = UserDefaults(suiteName: "test.crawl.maxboundary")!
        defaults.removePersistentDomain(forName: "test.crawl.maxboundary")
        defaults.set(CrawlConfiguration.maxDepthLimit, forKey: SettingsKey.maxCrawlDepth)

        let config = CrawlConfiguration.load(from: defaults)
        #expect(config.maxDepth == CrawlConfiguration.maxDepthLimit)
    }

    @Test func equatable() {
        let config1 = CrawlConfiguration(maxDepth: 15)
        let config2 = CrawlConfiguration(maxDepth: 15)
        let config3 = CrawlConfiguration(maxDepth: 20)

        #expect(config1 == config2)
        #expect(config1 != config3)
    }
}
