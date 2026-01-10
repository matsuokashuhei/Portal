//
//  ElectronAppDetectorTests.swift
//  PortalTests
//
//  Created by Claude Code on 2026/01/10.
//

import Testing
@testable import Portal

struct ElectronAppDetectorTests {
    let detector = ElectronAppDetector()

    // MARK: - Known Bundle ID Tests

    @Test func knownElectronBundleIDs_containsSlack() {
        #expect(ElectronAppDetector.knownElectronBundleIDs.contains("com.tinyspeck.slackmacgap"))
    }

    @Test func knownElectronBundleIDs_containsVSCode() {
        #expect(ElectronAppDetector.knownElectronBundleIDs.contains("com.microsoft.VSCode"))
    }

    @Test func knownElectronBundleIDs_containsDiscord() {
        #expect(ElectronAppDetector.knownElectronBundleIDs.contains("com.hnc.Discord"))
    }

    @Test func knownElectronBundleIDs_containsNotion() {
        #expect(ElectronAppDetector.knownElectronBundleIDs.contains("notion.id"))
    }

    @Test func knownElectronBundleIDs_containsFigma() {
        #expect(ElectronAppDetector.knownElectronBundleIDs.contains("com.figma.Desktop"))
    }

    @Test func knownElectronBundleIDs_contains1Password() {
        #expect(ElectronAppDetector.knownElectronBundleIDs.contains("com.1password.1password"))
    }

    @Test func knownElectronBundleIDs_containsObsidian() {
        #expect(ElectronAppDetector.knownElectronBundleIDs.contains("md.obsidian"))
    }

    @Test func knownElectronBundleIDs_containsPostman() {
        #expect(ElectronAppDetector.knownElectronBundleIDs.contains("com.postmanlabs.mac"))
    }

    @Test func knownElectronBundleIDs_containsMicrosoftTeams() {
        #expect(ElectronAppDetector.knownElectronBundleIDs.contains("com.microsoft.teams2"))
        #expect(ElectronAppDetector.knownElectronBundleIDs.contains("com.microsoft.teams"))
    }

    @Test func knownElectronBundleIDs_doesNotContainNativeApps() {
        // Verify native macOS apps are not in the list
        #expect(!ElectronAppDetector.knownElectronBundleIDs.contains("com.apple.finder"))
        #expect(!ElectronAppDetector.knownElectronBundleIDs.contains("com.apple.Safari"))
        #expect(!ElectronAppDetector.knownElectronBundleIDs.contains("com.apple.Music"))
        #expect(!ElectronAppDetector.knownElectronBundleIDs.contains("com.apple.systempreferences"))
    }

    // MARK: - Bundle ID Count

    @Test func knownElectronBundleIDs_hasReasonableCount() {
        // Should have at least the core apps documented
        #expect(ElectronAppDetector.knownElectronBundleIDs.count >= 10)
        // But not an unreasonable number
        #expect(ElectronAppDetector.knownElectronBundleIDs.count < 100)
    }
}
