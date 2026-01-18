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

    /// Known non-Electron apps that still expose AXWebArea (e.g., browsers).
    private static let knownNonElectronBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
        "company.thebrowser.Browser" // Arc
    ]

    private struct AXScanConfig {
        let maxDepth: Int
        let maxChildrenPerNode: Int
        let maxNodes: Int
    }

    private struct AXScanResult {
        var nodesScanned: Int = 0
        var webAreaCount: Int = 0
        var landmarkCount: Int = 0
        var documentCount: Int = 0
        var htmlContentCount: Int = 0
    }

    private enum AXHeuristic {
        static let detectionThreshold = 4
        static let scanConfig = AXScanConfig(maxDepth: 8, maxChildrenPerNode: 40, maxNodes: 800)
        static let logConfig = AXScanConfig(maxDepth: 12, maxChildrenPerNode: 80, maxNodes: 3000)
    }

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

        // Fallback: check Accessibility tree for Electron-like structure
        let axScore = accessibilityHeuristicScore(app)
        #if DEBUG
        print("[ElectronAppDetector] Electron AX score \(axScore) for \(app.bundleIdentifier ?? "unknown")")
        logAXTree(for: app, config: AXHeuristic.logConfig)
        #endif

        return axScore >= AXHeuristic.detectionThreshold
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

    private func accessibilityHeuristicScore(_ app: NSRunningApplication) -> Int {
        if let bundleID = app.bundleIdentifier,
           Self.knownNonElectronBundleIDs.contains(bundleID) {
            return 0
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        let windows = getAllWindows(from: axApp)
        guard !windows.isEmpty else {
            return 0
        }

        var result = AXScanResult()
        var visitedHashes = Set<CFHashCode>()
        for window in windows {
            scanAXTree(
                window,
                depth: 0,
                config: AXHeuristic.scanConfig,
                visited: &visitedHashes,
                result: &result
            )
        }

        var score = 0
        if result.webAreaCount > 0 { score += 4 }
        if result.htmlContentCount > 0 { score += 2 }
        if result.landmarkCount > 0 { score += 1 }
        if result.documentCount > 0 { score += 1 }

        return score
    }

    private func scanAXTree(
        _ element: AXUIElement,
        depth: Int,
        config: AXScanConfig,
        visited: inout Set<CFHashCode>,
        result: inout AXScanResult
    ) {
        guard depth <= config.maxDepth, result.nodesScanned < config.maxNodes else {
            return
        }

        let elementHash = CFHash(element)
        guard !visited.contains(elementHash) else {
            return
        }
        visited.insert(elementHash)
        result.nodesScanned += 1

        let role = getStringAttribute(element, kAXRoleAttribute as String)
        if role == "AXWebArea" {
            result.webAreaCount += 1
        }
        if role == "AXDocument" {
            result.documentCount += 1
        }
        if role?.hasPrefix("AXLandmark") == true {
            result.landmarkCount += 1
        }

        let roleDescription = getStringAttribute(element, kAXRoleDescriptionAttribute as String)
        let description = getStringAttribute(element, kAXDescriptionAttribute as String)
        if [roleDescription, description].compactMap({ $0 }).contains(where: { $0.localizedCaseInsensitiveContains("HTML") }) {
            result.htmlContentCount += 1
        }

        let children = getChildren(of: element)
        guard !children.isEmpty else {
            return
        }

        let limitedChildren = Array(children.prefix(config.maxChildrenPerNode))
        for child in limitedChildren {
            scanAXTree(child, depth: depth + 1, config: config, visited: &visited, result: &result)
        }
    }

    private func logAXTree(for app: NSRunningApplication, config: AXScanConfig) {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        let windows = getAllWindows(from: axApp)
        guard !windows.isEmpty else {
            print("[ElectronAppDetector] AX tree: no windows for \(app.bundleIdentifier ?? "unknown")")
            return
        }

        var visitedHashes = Set<CFHashCode>()
        var nodesLogged = 0
        for window in windows {
            logAXNode(
                window,
                depth: 0,
                config: config,
                visited: &visitedHashes,
                nodesLogged: &nodesLogged
            )
            if nodesLogged >= config.maxNodes {
                break
            }
        }
        if nodesLogged >= config.maxNodes {
            print("[ElectronAppDetector] AX tree: reached log limit (\(config.maxNodes) nodes)")
        }
    }

    private func logAXNode(
        _ element: AXUIElement,
        depth: Int,
        config: AXScanConfig,
        visited: inout Set<CFHashCode>,
        nodesLogged: inout Int
    ) {
        guard depth <= config.maxDepth, nodesLogged < config.maxNodes else {
            return
        }

        let elementHash = CFHash(element)
        guard !visited.contains(elementHash) else {
            return
        }
        visited.insert(elementHash)
        nodesLogged += 1

        let role = getStringAttribute(element, kAXRoleAttribute as String) ?? "unknown"
        let title = getStringAttribute(element, kAXTitleAttribute as String) ?? ""
        let desc = getStringAttribute(element, kAXRoleDescriptionAttribute as String) ?? ""
        let description = getStringAttribute(element, kAXDescriptionAttribute as String) ?? ""
        let value = getStringAttribute(element, kAXValueAttribute as String) ?? ""
        let help = getStringAttribute(element, kAXHelpAttribute as String) ?? ""
        let subrole = getStringAttribute(element, kAXSubroleAttribute as String) ?? ""

        let indent = String(repeating: "  ", count: depth)
        print("[ElectronAppDetector] \(indent)\(role) title='\(title)' desc='\(desc)' description='\(description)' value='\(value)' help='\(help)' subrole='\(subrole)'")

        let children = getChildren(of: element)
        if children.isEmpty || depth >= config.maxDepth {
            return
        }

        let limitedChildren = Array(children.prefix(config.maxChildrenPerNode))
        for child in limitedChildren {
            logAXNode(child, depth: depth + 1, config: config, visited: &visited, nodesLogged: &nodesLogged)
            if nodesLogged >= config.maxNodes {
                return
            }
        }
        if children.count > config.maxChildrenPerNode {
            let remaining = children.count - config.maxChildrenPerNode
            print("[ElectronAppDetector] \(indent)  ... \(remaining) more children omitted")
        }
    }

    private func getAllWindows(from axApp: AXUIElement) -> [AXUIElement] {
        var windows: [AXUIElement] = []

        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let ws = windowsRef as? [AXUIElement] {
            windows.append(contentsOf: ws)
        }

        var focusedWindowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindowRef) == .success,
           let fw = focusedWindowRef {
            // swiftlint:disable:next force_cast
            let focused = fw as! AXUIElement
            if !windows.contains(where: { CFEqual($0, focused) }) {
                windows.append(focused)
            }
        }

        if windows.isEmpty {
            var mainWindowRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axApp, kAXMainWindowAttribute as CFString, &mainWindowRef) == .success,
               let mw = mainWindowRef {
                // swiftlint:disable:next force_cast
                windows.append(mw as! AXUIElement)
            }
        }

        return windows
    }

    private func getChildren(of element: AXUIElement) -> [AXUIElement] {
        var combined: [AXUIElement] = []
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            combined.append(contentsOf: children)
        }

        var navChildrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXChildrenInNavigationOrder" as CFString, &navChildrenRef) == .success,
           let navChildren = navChildrenRef as? [AXUIElement] {
            combined.append(contentsOf: navChildren)
        }

        if combined.isEmpty {
            return []
        }

        var unique: [AXUIElement] = []
        for child in combined {
            if !unique.contains(where: { CFEqual($0, child) }) {
                unique.append(child)
            }
        }
        return unique
    }

    private func getStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef) == .success else {
            return nil
        }
        if let value = valueRef as? String {
            return value
        }
        if let url = valueRef as? URL {
            return url.absoluteString
        }
        return nil
    }
}
