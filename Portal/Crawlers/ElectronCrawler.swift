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
    // MARK: - ElementCrawler Protocol

    /// Electron apps use screen-local coordinates (no Y-flip needed).
    let coordinateSystem: HintCoordinateSystem = .electron

    // MARK: - Constants

    /// Cached maximum depth for the current crawl operation.
    /// Updated at the start of each crawl to pick up setting changes.
    private var cachedMaxDepth: Int = CrawlConfiguration.defaultMaxDepth

    /// Maximum number of items to return.
    private static let maxItems = 500

    /// The detector used to identify Electron apps.
    private let detector: ElectronAppDetector

    /// Native app crawler for handling native chrome elements.
    private let nativeCrawler: NativeAppCrawler

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
        "AXToolbar",  // Formatting toolbar, composer actions, etc.
        "AXTabGroup",  // Tab containers
        "AXOutline",  // Channel/DM list container
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

        // Load maxDepth once at the start of crawl for consistent behavior and performance
        cachedMaxDepth = CrawlConfiguration.load().maxDepth

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

    /// Crawls UI elements from the specified application as an async stream.
    ///
    /// This method yields elements as they are discovered, enabling progressive
    /// rendering of hint labels. Use this for better responsiveness when crawling
    /// applications with many UI elements.
    ///
    /// - Parameter app: The application to crawl elements from.
    /// - Returns: An async stream of discovered hint targets.
    func crawlElementsStream(_ app: NSRunningApplication) -> AsyncThrowingStream<HintTarget, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                guard AccessibilityService.isGranted else {
                    continuation.finish(throwing: NativeAppCrawlerError.accessibilityNotGranted)
                    return
                }

                // Load maxDepth once at the start of crawl for consistent behavior and performance
                self.cachedMaxDepth = CrawlConfiguration.load().maxDepth

                let pid = app.processIdentifier
                let axApp = AXUIElementCreateApplication(pid)

                // Enable enhanced accessibility for Electron apps
                self.enableAccessibility(for: axApp)

                // Track seen elements and frames for deduplication during streaming
                var seenElements: [AXUIElement] = []
                var seenFrames: [CGRect] = []
                var itemCount = 0

                let windows = self.getAllWindows(from: axApp)
                guard !windows.isEmpty else {
                    continuation.finish(throwing: NativeAppCrawlerError.mainWindowNotAccessible)
                    return
                }

                for windowElement in windows {
                    if Task.isCancelled {
                        continuation.finish()
                        return
                    }

                    // First, crawl AXWebArea elements (web content)
                    let webAreas = self.findWebAreas(in: windowElement, depth: 0)
                    for webArea in webAreas {
                        guard itemCount < Self.maxItems else { break }
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }
                        await self.crawlWebElementStreaming(
                            webArea,
                            depth: 0,
                            itemCount: &itemCount,
                            seenElements: &seenElements,
                            seenFrames: &seenFrames,
                            continuation: continuation
                        )
                    }

                    // Also crawl native chrome (toolbars, etc.)
                    if Task.isCancelled {
                        continuation.finish()
                        return
                    }
                    await self.crawlNativeChromeStreaming(
                        in: windowElement,
                        itemCount: &itemCount,
                        seenElements: &seenElements,
                        seenFrames: &seenFrames,
                        continuation: continuation
                    )
                }

                continuation.finish()
            }
        }
    }

    /// Checks if an element is a duplicate by AXUIElement reference.
    private func isDuplicate(_ element: AXUIElement, in seenElements: [AXUIElement]) -> Bool {
        return seenElements.contains { existing in
            CFEqual(existing, element)
        }
    }

    /// Checks if a frame significantly overlaps with any existing frame.
    private func hasFrameOverlap(_ frame: CGRect?, with seenFrames: [CGRect]) -> Bool {
        guard let itemFrame = frame, itemFrame != .zero else { return false }

        return seenFrames.contains { existingFrame in
            guard existingFrame != .zero else { return false }

            let intersection = itemFrame.intersection(existingFrame)
            guard !intersection.isNull else { return false }

            let itemArea = itemFrame.width * itemFrame.height
            let existingArea = existingFrame.width * existingFrame.height
            let intersectionArea = intersection.width * intersection.height
            let smallerArea = min(itemArea, existingArea)

            let overlapRatio = smallerArea > 0 ? intersectionArea / smallerArea : 0
            return overlapRatio > 0.5
        }
    }

    /// Crawls web elements within a web area, yielding results via continuation.
    private func crawlWebElementStreaming(
        _ element: AXUIElement,
        depth: Int,
        itemCount: inout Int,
        seenElements: inout [AXUIElement],
        seenFrames: inout [CGRect],
        continuation: AsyncThrowingStream<HintTarget, Error>.Continuation
    ) async {
        guard depth < cachedMaxDepth, itemCount < Self.maxItems else { return }
        if Task.isCancelled { return }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return
        }

        for child in children {
            guard itemCount < Self.maxItems else { break }
            if Task.isCancelled { return }

            guard let role = getRole(from: child) else { continue }

            let displayTitle = getDisplayTitle(from: child)

            // Electron web content: collect any element that has a usable frame.
            if let frame = getFrame(from: child),
               frame != .zero,
               frame.width > 0,
               frame.height > 0 {
                // Check for duplicates
                if !isDuplicate(child, in: seenElements) {
                    // Check for frame overlap
                    if !hasFrameOverlap(frame, with: seenFrames) {
                        seenElements.append(child)
                        seenFrames.append(frame)

                        let isEnabled = getIsEnabled(from: child)
                        let title = (displayTitle?.isEmpty == false) ? displayTitle! : role
                        let target = HintTarget(
                            title: title,
                            axElement: child,
                            isEnabled: isEnabled,
                            cachedFrame: frame,
                            targetType: .electron
                        )
                        continuation.yield(target)
                        itemCount += 1
                        // Yield to allow UI updates
                        await Task.yield()
                    }
                }
            }

            // Recurse into containers
            if Self.webContainerRoles.contains(role) || hasChildren(child) {
                await crawlWebElementStreaming(
                    child,
                    depth: depth + 1,
                    itemCount: &itemCount,
                    seenElements: &seenElements,
                    seenFrames: &seenFrames,
                    continuation: continuation
                )
            }
        }
    }

    /// Crawls native chrome elements, yielding results via continuation.
    private func crawlNativeChromeStreaming(
        in element: AXUIElement,
        itemCount: inout Int,
        seenElements: inout [AXUIElement],
        seenFrames: inout [CGRect],
        continuation: AsyncThrowingStream<HintTarget, Error>.Continuation
    ) async {
        if Task.isCancelled { return }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return
        }

        for child in children {
            guard itemCount < Self.maxItems else { break }
            if Task.isCancelled { return }

            guard let role = getRole(from: child) else { continue }

            // Skip web areas (already crawled)
            if role == "AXWebArea" { continue }

            // Electron native chrome: collect any element that has a usable frame.
            if let frame = getFrame(from: child),
               frame != .zero,
               frame.width > 0,
               frame.height > 0 {
                if !isDuplicate(child, in: seenElements) {
                    if !hasFrameOverlap(frame, with: seenFrames) {
                        seenElements.append(child)
                        seenFrames.append(frame)

                        let isEnabled = getIsEnabled(from: child)
                        let displayTitle = getDisplayTitle(from: child)
                        let title = (displayTitle?.isEmpty == false) ? displayTitle! : role
                        let target = HintTarget(
                            title: title,
                            axElement: child,
                            isEnabled: isEnabled,
                            cachedFrame: frame,
                            targetType: .electron
                        )
                        continuation.yield(target)
                        itemCount += 1
                        // Yield to allow UI updates
                        await Task.yield()
                    }
                }
            }

            // Recurse into native containers (but not web areas)
            if isNativeContainerRole(role) {
                await crawlNativeChromeStreaming(
                    in: child,
                    itemCount: &itemCount,
                    seenElements: &seenElements,
                    seenFrames: &seenFrames,
                    continuation: continuation
                )
            }
        }
    }

    // MARK: - Accessibility Enhancement

    /// Enables enhanced accessibility for the Electron app.
    ///
    /// This sets AXManualAccessibility and AXEnhancedUserInterface attributes
    /// to expose web content elements through the accessibility API.
    ///
    /// ## Design Decision: No Restoration
    ///
    /// These settings are intentionally NOT restored when hint mode ends because:
    /// 1. **User Experience**: Restoring would require re-enabling on every activation,
    ///    adding latency and potentially causing flickering in Electron apps.
    /// 2. **No Negative Impact**: These settings only expose MORE accessibility information,
    ///    which benefits screen readers and other assistive technologies.
    /// 3. **App Scope**: Settings are per-application and don't affect other apps.
    /// 4. **Persistence**: macOS may cache these settings anyway, making restoration
    ///    ineffective in some cases.
    ///
    /// If restoration becomes necessary (e.g., conflicts with specific assistive tech),
    /// implement by storing original values and restoring in HintModeController.deactivate().
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
        Self.roleCountsForDebug.removeAll()
        #endif

        for webArea in webAreas {
            guard itemCount < Self.maxItems else { break }
            let items = crawlWebElement(webArea, depth: 0, itemCount: &itemCount)
            results.append(contentsOf: items)
        }

        #if DEBUG
        // Print role distribution summary
        print("[ElectronCrawler] === Role Distribution Summary ===")
        for (role, count) in Self.roleCountsForDebug.sorted(by: { $0.value > $1.value }) {
            print("[ElectronCrawler]   \(role): \(count)")
        }
        print("[ElectronCrawler] ================================")
        #endif

        return results
    }

    /// Recursively finds AXWebArea elements.
    private func findWebAreas(in element: AXUIElement, depth: Int) -> [AXUIElement] {
        guard depth < cachedMaxDepth else { return [] }

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

    #if DEBUG
    /// Tracks role counts for debugging
    private static var roleCountsForDebug: [String: Int] = [:]
    #endif

    /// Crawls web elements within a web area.
    private func crawlWebElement(_ element: AXUIElement, depth: Int, itemCount: inout Int) -> [HintTarget] {
        guard depth < cachedMaxDepth, itemCount < Self.maxItems else {
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

            #if DEBUG
            Self.roleCountsForDebug[role, default: 0] += 1
            #endif

            // Electron web content: collect any element that has a usable frame.
            if let frame = getFrame(from: child),
               frame != .zero,
               frame.width > 0,
               frame.height > 0 {
                let isEnabled = getIsEnabled(from: child)
                let title = (displayTitle?.isEmpty == false) ? displayTitle! : role
                let target = HintTarget(
                    title: title,
                    axElement: child,
                    isEnabled: isEnabled,
                    cachedFrame: frame,
                    targetType: .electron
                )
                items.append(target)
                itemCount += 1

                #if DEBUG
                if depth <= 3 {
                    print("[ElectronCrawler] Adding web item: '\(title)' (role: \(role)) frame=\(frame.debugDescription)")
                }
                #endif
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

            // Electron native chrome: collect any element that has a usable frame.
            if let frame = getFrame(from: child),
               frame != .zero,
               frame.width > 0,
               frame.height > 0 {
                let isEnabled = getIsEnabled(from: child)
                let displayTitle = getDisplayTitle(from: child)
                let title = (displayTitle?.isEmpty == false) ? displayTitle! : role
                let target = HintTarget(
                    title: title,
                    axElement: child,
                    isEnabled: isEnabled,
                    cachedFrame: frame,
                    targetType: .electron
                )
                items.append(target)
                itemCount += 1

                #if DEBUG
                print("[ElectronCrawler] Adding native item: '\(title)' (role: \(role)) frame=\(frame.debugDescription)")
                #endif
            }

            // Recurse into native containers (but not web areas)
            if isNativeContainerRole(role) {
                items.append(contentsOf: crawlNativeChrome(in: child, itemCount: &itemCount))
            }
        }

        return items
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
            // Note: CoreFoundation types require force cast as conditional cast (as?) always succeeds.
            // The cast is safe because AXUIElementCopyAttributeValue guarantees the correct type on success.
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
                // Note: CoreFoundation types require force cast as conditional cast (as?) always succeeds.
                // The cast is safe because AXUIElementCopyAttributeValue guarantees the correct type on success.
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

    /// Gets the frame (position + size) of an element.
    private func getFrame(from element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero

        // Note: CoreFoundation types require force cast as conditional cast (as?) always succeeds.
        // The cast is safe because AXUIElementCopyAttributeValue guarantees the correct type on success.
        // swiftlint:disable force_cast
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        // swiftlint:enable force_cast

        return CGRect(origin: position, size: size)
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

        // Also deduplicate based on overlapping frames
        // This handles cases where icon and text label are separate elements
        return deduplicateByFrame(uniqueItems)
    }

    /// Removes items with overlapping frames, keeping the first one encountered.
    ///
    /// In Electron apps, a single UI element (like a sidebar item) may contain
    /// multiple accessible elements (icon, text label) that each have their own
    /// hint. This method removes duplicates based on frame overlap.
    private func deduplicateByFrame(_ items: [HintTarget]) -> [HintTarget] {
        var result: [HintTarget] = []

        for item in items {
            guard let itemFrame = item.cachedFrame, itemFrame != .zero else {
                // No frame - keep it
                result.append(item)
                continue
            }

            // Check if this item's frame significantly overlaps with any existing item
            let hasOverlap = result.contains { existing in
                guard let existingFrame = existing.cachedFrame, existingFrame != .zero else {
                    return false
                }

                // Calculate intersection
                let intersection = itemFrame.intersection(existingFrame)
                guard !intersection.isNull else {
                    return false
                }

                // Calculate overlap ratio (relative to smaller frame)
                let itemArea = itemFrame.width * itemFrame.height
                let existingArea = existingFrame.width * existingFrame.height
                let intersectionArea = intersection.width * intersection.height
                let smallerArea = min(itemArea, existingArea)

                // If overlap is more than 50% of smaller frame, consider duplicate
                let overlapRatio = smallerArea > 0 ? intersectionArea / smallerArea : 0
                return overlapRatio > 0.5
            }

            if !hasOverlap {
                result.append(item)
            } else {
                #if DEBUG
                print("[ElectronCrawler] Dedup by frame: Skipping '\(item.title)' (overlaps with existing)")
                #endif
            }
        }

        return result
    }
}
