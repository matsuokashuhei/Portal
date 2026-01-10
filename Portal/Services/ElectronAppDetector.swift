//
//  ElectronAppDetector.swift
//  Portal
//
//  Created by Claude Code on 2026/01/10.
//

import AppKit

/// Detects whether an application is built with Electron.
///
/// Electron apps are web-based desktop applications that use Chromium for rendering.
/// They can be identified by:
/// 1. Known Bundle IDs (most reliable)
/// 2. Presence of Electron.framework in the app bundle (fallback)
///
/// ## Supported Electron Apps
/// - Slack (`com.tinyspeck.slackmacgap`)
/// - VS Code (`com.microsoft.VSCode`)
/// - Discord (`com.hnc.Discord`)
/// - Notion (`notion.id`)
/// - Figma (`com.figma.Desktop`)
/// - 1Password (`com.1password.1password`)
/// - Obsidian (`md.obsidian`)
/// - Postman (`com.postmanlabs.mac`)
/// - Todoist (`com.todoist.mac.Todoist`)
///
/// ## Usage
/// ```swift
/// let detector = ElectronAppDetector()
/// if detector.isElectronApp(app) {
///     // Use Electron-specific handling
/// }
/// ```
final class ElectronAppDetector {
    /// Known Electron app Bundle IDs.
    ///
    /// This list is used for fast detection without filesystem checks.
    /// Add new Electron apps here as they are identified.
    static let knownElectronBundleIDs: Set<String> = [
        // Communication
        "com.tinyspeck.slackmacgap",  // Slack
        "com.hnc.Discord",             // Discord
        "com.microsoft.teams2",        // Microsoft Teams (new)
        "com.microsoft.teams",         // Microsoft Teams (old)

        // Development
        "com.microsoft.VSCode",        // VS Code
        "com.postmanlabs.mac",         // Postman
        "com.github.GitHubClient",     // GitHub Desktop

        // Productivity
        "notion.id",                   // Notion
        "com.figma.Desktop",           // Figma
        "md.obsidian",                 // Obsidian
        "com.todoist.mac.Todoist",     // Todoist
        "com.linear",                  // Linear

        // Utilities
        "com.1password.1password",     // 1Password 8
        "com.bitwarden.desktop",       // Bitwarden
    ]

    /// Checks if the given application is an Electron app.
    ///
    /// Detection is performed in two stages:
    /// 1. Check against known Bundle IDs (fast)
    /// 2. Check for Electron.framework in the app bundle (slower, but catches unknown apps)
    ///
    /// - Parameter app: The application to check.
    /// - Returns: `true` if the app is an Electron app, `false` otherwise.
    func isElectronApp(_ app: NSRunningApplication) -> Bool {
        // Fast path: check known Bundle IDs
        if let bundleID = app.bundleIdentifier,
           Self.knownElectronBundleIDs.contains(bundleID) {
            #if DEBUG
            print("[ElectronAppDetector] Detected Electron app by Bundle ID: \(bundleID)")
            #endif
            return true
        }

        // Slow path: check for Electron.framework
        if hasElectronFramework(app) {
            #if DEBUG
            print("[ElectronAppDetector] Detected Electron app by framework: \(app.bundleIdentifier ?? "unknown")")
            #endif
            return true
        }

        return false
    }

    /// Checks if the application contains Electron.framework.
    ///
    /// Electron apps typically have the framework at:
    /// `Contents/Frameworks/Electron Framework.framework`
    ///
    /// - Parameter app: The application to check.
    /// - Returns: `true` if Electron.framework is found.
    private func hasElectronFramework(_ app: NSRunningApplication) -> Bool {
        guard let bundleURL = app.bundleURL else {
            return false
        }

        let frameworkPath = bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Frameworks")
            .appendingPathComponent("Electron Framework.framework")

        let exists = FileManager.default.fileExists(atPath: frameworkPath.path)

        #if DEBUG
        if exists {
            print("[ElectronAppDetector] Found Electron Framework at: \(frameworkPath.path)")
        }
        #endif

        return exists
    }
}
