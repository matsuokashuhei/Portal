//
//  ElectronCrawler.swift
//  Portal
//
//  Created by Claude Code on 2026/01/10.
//

import ApplicationServices
import AppKit

/// Crawler specialized for Electron applications.
///
/// Electron apps use Chromium for rendering web content, which requires special handling:
/// 1. Enable AXManualAccessibility to expose web elements
/// 2. Crawl AXWebArea elements for web content
/// 3. Also crawl native chrome (toolbars, sidebars) using standard accessibility
///
/// ## Supported Electron Apps
/// - Slack, VS Code, Discord, Notion, Figma, 1Password, Obsidian, etc.
///
/// ## Web Element Roles
/// - AXLink - Links
/// - AXButton - Buttons
/// - AXTextField / AXTextArea - Input fields
/// - AXCheckBox / AXRadioButton - Form elements
/// - AXMenuItem - Menu items
/// - AXWebArea - Web content containers
@MainActor
final class ElectronCrawler: ElementCrawler {
    /// Maximum depth for recursive traversal.
    private static let maxDepth = 15  // Deeper than native due to web DOM structure

    /// Maximum number of items to return.
    private static let maxItems = 500

    /// The detector used to identify Electron apps.
    private let detector: ElectronAppDetector

    /// Native app crawler for handling native chrome elements.
    private let nativeCrawler: NativeAppCrawler

    /// Web element roles we're interested in.
    private static let webItemRoles: Set<String> = [
        "AXLink",
        "AXButton",
        "AXTextField",
        "AXTextArea",
        "AXCheckBox",
        "AXRadioButton",
        "AXMenuItem",
        "AXMenuItemCheckbox",
        "AXMenuItemRadio",
        "AXTab",
        "AXStaticText",  // Sometimes used for clickable text
    ]

    /// Container roles that should be traversed.
    private static let webContainerRoles: Set<String> = [
        "AXWebArea",
        "AXGroup",
        "AXList",
        "AXTable",
        "AXScrollArea",
        "AXSection",
        "AXLandmarkMain",
        "AXLandmarkNavigation",
        "AXLandmarkBanner",
        "AXArticle",
        "AXGenericContainer",  // Common in web content
    ]

    /// Creates an ElectronCrawler with the default detector.
    init() {
        self.detector = ElectronAppDetector()
        self.nativeCrawler = NativeAppCrawler()
    }

    /// Creates an ElectronCrawler with a custom detector (for testing).
    init(detector: ElectronAppDetector, nativeCrawler: NativeAppCrawler) {
        self.detector = detector
        self.nativeCrawler = nativeCrawler
    }

    // MARK: - ElementCrawler Protocol

    func canHandle(_ app: NSRunningApplication) -> Bool {
        return detector.isElectronApp(app)
    }

    func crawlElements(_ app: NSRunningApplication) async throws -> [HintTarget] {
        guard AccessibilityService.isGranted else {
            throw NativeAppCrawlerError.accessibilityNotGranted
        }

        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)

        #if DEBUG
        print("[ElectronCrawler] Crawling Electron app: \(app.bundleIdentifier ?? "unknown")")
        #endif

        // Enable enhanced accessibility for Electron apps
        enableAccessibility(for: axApp)

        var itemCount = 0
        var allItems: [HintTarget] = []

        // Get all windows
        let windows = getAllWindows(from: axApp)
        guard !windows.isEmpty else {
            throw NativeAppCrawlerError.mainWindowNotAccessible
        }

        for windowElement in windows {
            let windowTitle = getTitle(from: windowElement) ?? app.localizedName ?? "Window"
            #if DEBUG
            print("[ElectronCrawler] Crawling window: '\(windowTitle)'")
            #endif

            // First, try to find and crawl AXWebArea elements (web content)
            let webItems = crawlWebAreas(in: windowElement, itemCount: &itemCount)
            allItems.append(contentsOf: webItems)

            #if DEBUG
            print("[ElectronCrawler] Found \(webItems.count) web items")
            #endif

            // Also crawl native chrome (toolbars, etc.) using standard approach
            let nativeItems = crawlNativeChrome(in: windowElement, itemCount: &itemCount)
            allItems.append(contentsOf: nativeItems)

            #if DEBUG
            print("[ElectronCrawler] Found \(nativeItems.count) native items")
            #endif
        }

        // Deduplicate based on AXUIElement reference
        return deduplicateItems(allItems)
    }

    // MARK: - Accessibility Enhancement

    /// Enables enhanced accessibility for the Electron app.
    ///
    /// This sets AXManualAccessibility and AXEnhancedUserInterface attributes
    /// to expose web content elements through the accessibility API.
    private func enableAccessibility(for axApp: AXUIElement) {
        // Try AXManualAccessibility first (preferred for Electron)
        let manualResult = AXUIElementSetAttributeValue(
            axApp,
            "AXManualAccessibility" as CFString,
            kCFBooleanTrue
        )

        #if DEBUG
        print("[ElectronCrawler] AXManualAccessibility set result: \(manualResult.rawValue)")
        #endif

        // Also try AXEnhancedUserInterface as fallback
        let enhancedResult = AXUIElementSetAttributeValue(
            axApp,
            "AXEnhancedUserInterface" as CFString,
            kCFBooleanTrue
        )

        #if DEBUG
        print("[ElectronCrawler] AXEnhancedUserInterface set result: \(enhancedResult.rawValue)")
        #endif
    }

    // MARK: - Web Content Crawling

    /// Crawls AXWebArea elements within a window.
    private func crawlWebAreas(in element: AXUIElement, itemCount: inout Int) -> [HintTarget] {
        var results: [HintTarget] = []

        // Find all AXWebArea elements
        let webAreas = findWebAreas(in: element, depth: 0)

        #if DEBUG
        print("[ElectronCrawler] Found \(webAreas.count) AXWebArea elements")
        #endif

        for webArea in webAreas {
            guard itemCount < Self.maxItems else { break }
            let items = crawlWebElement(webArea, depth: 0, itemCount: &itemCount)
            results.append(contentsOf: items)
        }

        return results
    }

    /// Recursively finds AXWebArea elements.
    private func findWebAreas(in element: AXUIElement, depth: Int) -> [AXUIElement] {
        guard depth < Self.maxDepth else { return [] }

        var webAreas: [AXUIElement] = []

        // Check if this element is a web area
        if let role = getRole(from: element), role == "AXWebArea" {
            webAreas.append(element)
        }

        // Check children
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return webAreas
        }

        for child in children {
            webAreas.append(contentsOf: findWebAreas(in: child, depth: depth + 1))
        }

        return webAreas
    }

    /// Crawls web elements within a web area.
    private func crawlWebElement(_ element: AXUIElement, depth: Int, itemCount: inout Int) -> [HintTarget] {
        guard depth < Self.maxDepth, itemCount < Self.maxItems else {
            return []
        }

        var items: [HintTarget] = []

        // Get children
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return items
        }

        for child in children {
            guard itemCount < Self.maxItems else { break }

            guard let role = getRole(from: child) else { continue }

            // Get display title
            let displayTitle = getDisplayTitle(from: child)

            // Check if this is an actionable web element
            if Self.webItemRoles.contains(role) {
                if let title = displayTitle, !title.isEmpty, canPerformAction(on: child) {
                    let isEnabled = getIsEnabled(from: child)
                    let target = HintTarget(
                        title: title,
                        axElement: child,
                        isEnabled: isEnabled
                    )
                    items.append(target)
                    itemCount += 1

                    #if DEBUG
                    if depth <= 3 {
                        print("[ElectronCrawler] Adding web item: '\(title)' (role: \(role))")
                    }
                    #endif
                }
            }

            // Recurse into containers
            if Self.webContainerRoles.contains(role) || hasChildren(child) {
                items.append(contentsOf: crawlWebElement(child, depth: depth + 1, itemCount: &itemCount))
            }
        }

        return items
    }

    // MARK: - Native Chrome Crawling

    /// Crawls native chrome elements (toolbars, sidebars, etc.).
    ///
    /// These are elements outside of the web content area that use standard
    /// macOS accessibility.
    private func crawlNativeChrome(in element: AXUIElement, itemCount: inout Int) -> [HintTarget] {
        var items: [HintTarget] = []

        // Get children
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return items
        }

        for child in children {
            guard itemCount < Self.maxItems else { break }

            guard let role = getRole(from: child) else { continue }

            // Skip web areas (already crawled)
            if role == "AXWebArea" {
                continue
            }

            // Check for actionable native elements
            if isNativeActionableRole(role) {
                if let title = getDisplayTitle(from: child), !title.isEmpty, canPerformAction(on: child) {
                    let isEnabled = getIsEnabled(from: child)
                    let target = HintTarget(
                        title: title,
                        axElement: child,
                        isEnabled: isEnabled
                    )
                    items.append(target)
                    itemCount += 1

                    #if DEBUG
                    print("[ElectronCrawler] Adding native item: '\(title)' (role: \(role))")
                    #endif
                }
            }

            // Recurse into native containers (but not web areas)
            if isNativeContainerRole(role) {
                items.append(contentsOf: crawlNativeChrome(in: child, itemCount: &itemCount))
            }
        }

        return items
    }

    /// Checks if a role is an actionable native element.
    private func isNativeActionableRole(_ role: String) -> Bool {
        let nativeActionableRoles: Set<String> = [
            "AXButton", "AXRadioButton", "AXCheckBox", "AXMenuItem",
            "AXMenuButton", "AXPopUpButton", "AXComboBox", "AXTextField",
            "AXRow", "AXCell", "AXOutlineRow", "AXSwitch", "AXTab"
        ]
        return nativeActionableRoles.contains(role)
    }

    /// Checks if a role is a native container.
    private func isNativeContainerRole(_ role: String) -> Bool {
        let nativeContainerRoles: Set<String> = [
            "AXToolbar", "AXGroup", "AXSplitGroup", "AXScrollArea",
            "AXOutline", "AXList", "AXTable", "AXTabGroup"
        ]
        return nativeContainerRoles.contains(role)
    }

    // MARK: - Helper Methods

    /// Gets all windows from an application.
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

    /// Gets display title from an element.
    private func getDisplayTitle(from element: AXUIElement) -> String? {
        // Try various title sources
        if let title = getTitle(from: element), !title.isEmpty {
            return title
        }
        if let desc = getDescription(from: element), !desc.isEmpty {
            return desc
        }
        if let value = getValue(from: element), !value.isEmpty {
            return value
        }
        if let help = getHelp(from: element), !help.isEmpty {
            return help
        }

        // For links, try URL as fallback
        if let role = getRole(from: element), role == "AXLink" {
            if let url = getURL(from: element), !url.isEmpty {
                // Extract domain or last path component
                if let urlObj = URL(string: url) {
                    return urlObj.lastPathComponent.isEmpty ? urlObj.host : urlObj.lastPathComponent
                }
            }
        }

        return nil
    }

    /// Gets the title attribute.
    private func getTitle(from element: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success else {
            return nil
        }
        return titleRef as? String
    }

    /// Gets the description attribute.
    private func getDescription(from element: AXUIElement) -> String? {
        var descRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef) == .success else {
            return nil
        }
        return descRef as? String
    }

    /// Gets the value attribute.
    private func getValue(from element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success else {
            return nil
        }
        return valueRef as? String
    }

    /// Gets the help attribute.
    private func getHelp(from element: AXUIElement) -> String? {
        var helpRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXHelpAttribute as CFString, &helpRef) == .success else {
            return nil
        }
        return helpRef as? String
    }

    /// Gets the URL attribute (for links).
    private func getURL(from element: AXUIElement) -> String? {
        var urlRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXURL" as CFString, &urlRef) == .success else {
            return nil
        }
        if let url = urlRef as? URL {
            return url.absoluteString
        }
        return urlRef as? String
    }

    /// Gets the role attribute.
    private func getRole(from element: AXUIElement) -> String? {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success else {
            return nil
        }
        return roleRef as? String
    }

    /// Checks if an element has children.
    private func hasChildren(_ element: AXUIElement) -> Bool {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return false
        }
        return !children.isEmpty
    }

    /// Checks if an action can be performed on an element.
    private func canPerformAction(on element: AXUIElement) -> Bool {
        var actionsRef: CFArray?
        guard AXUIElementCopyActionNames(element, &actionsRef) == .success,
              let actions = actionsRef as? [String] else {
            return false
        }

        return actions.contains(kAXPressAction as String) ||
               actions.contains("AXSelect") ||
               actions.contains("AXConfirm") ||
               actions.contains("AXShowDefaultUI") ||
               actions.contains("AXPick")
    }

    /// Gets the enabled state.
    private func getIsEnabled(from element: AXUIElement) -> Bool {
        var enabledRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabledRef) == .success else {
            return true
        }
        return (enabledRef as? Bool) ?? true
    }

    /// Removes duplicate items based on AXUIElement reference.
    private func deduplicateItems(_ items: [HintTarget]) -> [HintTarget] {
        var seenElements: [AXUIElement] = []
        var uniqueItems: [HintTarget] = []

        for item in items {
            let isDuplicate = seenElements.contains { existing in
                CFEqual(existing, item.axElement)
            }

            if !isDuplicate {
                seenElements.append(item.axElement)
                uniqueItems.append(item)
            }
        }

        return uniqueItems
    }
}
