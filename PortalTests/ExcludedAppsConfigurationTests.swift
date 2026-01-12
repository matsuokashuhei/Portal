//
//  ExcludedAppsConfigurationTests.swift
//  PortalTests
//
//  Created by Claude Code on 2026/01/12.
//

import Foundation
import Testing
@testable import Portal

struct ExcludedAppsConfigurationTests {

    // MARK: - Test Helper

    /// Creates a unique test suite name for each test run to avoid parallel test conflicts.
    /// Uses UUID to ensure complete isolation between concurrent test processes.
    private func withIsolatedDefaults(_ body: (UserDefaults) -> Void) {
        let testSuiteName = "com.portal.test.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: testSuiteName)!

        defer {
            // Clean up the test suite
            testDefaults.removePersistentDomain(forName: testSuiteName)
        }

        body(testDefaults)
    }

    // MARK: - Default Configuration Tests

    @Test
    func testDefaultConfiguration() {
        let config = ExcludedAppsConfiguration.default

        #expect(config.excludedApps.isEmpty)
    }

    // MARK: - ExcludedApp Tests

    @Test
    func testExcludedAppIdentifiable() {
        let app = ExcludedApp(bundleIdentifier: "com.example.app", displayName: "Example App")

        #expect(app.id == "com.example.app")
    }

    @Test
    func testExcludedAppEquality() {
        let app1 = ExcludedApp(bundleIdentifier: "com.example.app", displayName: "Example App")
        let app2 = ExcludedApp(bundleIdentifier: "com.example.app", displayName: "Example App")
        let app3 = ExcludedApp(bundleIdentifier: "com.other.app", displayName: "Other App")

        #expect(app1 == app2)
        #expect(app1 != app3)
    }

    // MARK: - Persistence Tests

    @Test
    func testSaveAndLoad() {
        withIsolatedDefaults { defaults in
            // Save a configuration with excluded apps
            let app1 = ExcludedApp(bundleIdentifier: "com.microsoft.VSCode", displayName: "Visual Studio Code")
            let app2 = ExcludedApp(bundleIdentifier: "com.apple.Terminal", displayName: "Terminal")
            let config = ExcludedAppsConfiguration(excludedApps: [app1, app2])
            config.save(to: defaults)

            // Load and verify
            let loaded = ExcludedAppsConfiguration.load(from: defaults)
            #expect(loaded.excludedApps.count == 2)
            #expect(loaded.excludedApps[0].bundleIdentifier == "com.microsoft.VSCode")
            #expect(loaded.excludedApps[0].displayName == "Visual Studio Code")
            #expect(loaded.excludedApps[1].bundleIdentifier == "com.apple.Terminal")
            #expect(loaded.excludedApps[1].displayName == "Terminal")
        }
    }

    @Test
    func testLoadWithEmptyReturnsDefault() {
        withIsolatedDefaults { defaults in
            // defaults is empty by default, so just load
            let loaded = ExcludedAppsConfiguration.load(from: defaults)
            #expect(loaded.excludedApps.isEmpty)
        }
    }

    @Test
    func testLoadWithInvalidJSONReturnsDefault() {
        withIsolatedDefaults { defaults in
            // Set invalid JSON data
            defaults.set("invalid json".data(using: .utf8), forKey: SettingsKey.excludedApps)

            // Load and verify defaults are returned
            let loaded = ExcludedAppsConfiguration.load(from: defaults)
            #expect(loaded.excludedApps.isEmpty)
        }
    }

    @Test
    func testLoadWithMalformedDataReturnsDefault() {
        withIsolatedDefaults { defaults in
            // Set malformed data (valid JSON but wrong structure)
            let malformed = try! JSONEncoder().encode(["not": "an array"])
            defaults.set(malformed, forKey: SettingsKey.excludedApps)

            // Load and verify defaults are returned
            let loaded = ExcludedAppsConfiguration.load(from: defaults)
            #expect(loaded.excludedApps.isEmpty)
        }
    }

    // MARK: - isExcluded Tests

    @Test
    func testIsExcludedReturnsTrue() {
        let app = ExcludedApp(bundleIdentifier: "com.example.app", displayName: "Example App")
        let config = ExcludedAppsConfiguration(excludedApps: [app])

        #expect(config.isExcluded(bundleIdentifier: "com.example.app"))
    }

    @Test
    func testIsExcludedReturnsFalse() {
        let app = ExcludedApp(bundleIdentifier: "com.example.app", displayName: "Example App")
        let config = ExcludedAppsConfiguration(excludedApps: [app])

        #expect(!config.isExcluded(bundleIdentifier: "com.other.app"))
    }

    @Test
    func testIsExcludedWithEmptyList() {
        let config = ExcludedAppsConfiguration(excludedApps: [])

        #expect(!config.isExcluded(bundleIdentifier: "com.example.app"))
    }

    @Test
    func testIsExcludedWithMultipleApps() {
        let apps = [
            ExcludedApp(bundleIdentifier: "com.microsoft.VSCode", displayName: "VS Code"),
            ExcludedApp(bundleIdentifier: "com.apple.Terminal", displayName: "Terminal"),
            ExcludedApp(bundleIdentifier: "com.googlecode.iterm2", displayName: "iTerm2")
        ]
        let config = ExcludedAppsConfiguration(excludedApps: apps)

        #expect(config.isExcluded(bundleIdentifier: "com.microsoft.VSCode"))
        #expect(config.isExcluded(bundleIdentifier: "com.apple.Terminal"))
        #expect(config.isExcluded(bundleIdentifier: "com.googlecode.iterm2"))
        #expect(!config.isExcluded(bundleIdentifier: "com.apple.finder"))
    }

    // MARK: - Equality Tests

    @Test
    func testConfigurationEquality() {
        let app = ExcludedApp(bundleIdentifier: "com.example.app", displayName: "Example App")
        let config1 = ExcludedAppsConfiguration(excludedApps: [app])
        let config2 = ExcludedAppsConfiguration(excludedApps: [app])
        let config3 = ExcludedAppsConfiguration(excludedApps: [])

        #expect(config1 == config2)
        #expect(config1 != config3)
    }
}
