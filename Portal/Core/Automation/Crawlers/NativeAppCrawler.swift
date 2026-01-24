//
//  NativeAppCrawler.swift
//  Portal
//
//  Created by Claude Code on 2026/01/02.
//  Renamed from WindowCrawler on 2026/01/10.
//

import ApplicationServices
import AppKit
import Logging

private let logger = PortalLogger.make("Portal", category: "NativeAppCrawler")

/// Error types for native app crawling operations.
enum NativeAppCrawlerError: Error, LocalizedError {
    case accessibilityNotGranted
    case noActiveApplication
    case mainWindowNotAccessible

    var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            return "Portal needs Accessibility permission to read window elements. Please enable access in System Settings > Privacy & Security > Accessibility."
        case .noActiveApplication:
            return "No active application found. Click on an app window to make it active, then try again."
        case .mainWindowNotAccessible:
            return "Unable to access this app's main window. The app may not have a visible window or may have quit."
        }
    }
}

/// Service for crawling window UI elements using Accessibility API.
///
/// This service crawls actionable UI elements from an application's main window,
/// including sidebars, toolbars, and content areas.
///
/// ## Supported Applications
/// - Apple Music (Library, Playlists)
/// - Finder (Favorites, Locations, Files)
/// - Notes (Folders)
/// - Mail (Mailboxes)
/// - System Settings (navigation items)
///
/// ## Performance
/// Window crawling typically takes 50-200ms depending on UI complexity.
/// No caching is used because window content can change
/// more frequently (e.g., when navigating folders).
///
/// ## Known Limitations
/// Some applications have UI elements that are visible in Accessibility Inspector
/// but are not exposed through the standard `kAXChildrenAttribute` API. For example:
/// - **Xcode Debug Area**: The "Show the Variables View" and "Show the Console"
///   toggle buttons (AXCheckBox with AXToggle subrole) are visible in Accessibility
///   Inspector but not returned by the API. This appears to be a limitation in
///   Xcode's accessibility implementation.
///
/// These elements cannot be targeted by hint labels because they are not discoverable
/// through the Accessibility API that Portal uses.
@MainActor
final class NativeAppCrawler: ElementCrawler {
    // MARK: - ElementCrawler Protocol

    /// Native macOS apps use Accessibility API coordinates (top-left origin).
    let coordinateSystem: HintCoordinateSystem = .native

    // MARK: - Constants

    /// Cached maximum depth for the current crawl operation.
    /// Updated at the start of each crawl to pick up setting changes.
    private var cachedMaxDepth: Int = CrawlConfiguration.defaultMaxDepth

    /// Maximum number of items to return (performance safeguard).
    /// Increased from 200 to 500 to ensure player controls and other UI elements
    /// are crawled even when there are many content items (e.g., search results).
    private static let maxItems = 500

    /// Accessibility roles for container elements that should be traversed.
    private static let containerRoles: Set<String> = [
        "AXOutline",
        "AXList",
        "AXTable",
        "AXScrollArea",
        "AXSplitGroup",
        "AXGroup",
        "AXToolbar",
        "AXSegmentedControl",
        // Needed to crawl popup/select menus (e.g., System Settings select boxes)
        "AXMenu"
    ]

    /// Accessibility roles for actionable items we can interact with.
    private static let itemRoles: Set<String> = [
        "AXRow",
        "AXCell",
        "AXOutlineRow",
        "AXStaticText",
        "AXButton",
        "AXRadioButton",
        // Needed to support popup/select menus
        "AXMenuItem",
        "AXCheckBox",
        "AXMenuButton",
        "AXSwitch",
        "AXPopUpButton",
        "AXComboBox",
        "AXTextField",
        // Additional controls (#132)
        "AXSlider",              // Volume, brightness sliders
        "AXIncrementor",         // Numeric steppers
        "AXDisclosureTriangle",  // Expand/collapse triangles
        "AXTab",                 // Tab selection
        "AXSegment"              // Individual segment buttons
    ]

    // MARK: - ElementCrawler Protocol

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

                guard let windowElement = AccessibilityHelper.getMainWindow(app) else {
                    continuation.finish(throwing: NativeAppCrawlerError.mainWindowNotAccessible)
                    return
                }

                // Check for cancellation
                if Task.isCancelled {
                    continuation.finish()
                    return
                }

                // Load maxDepth once at the start of crawl for consistent behavior and performance
                self.cachedMaxDepth = CrawlConfiguration.load().maxDepth


                // Get window control buttons and yield them immediately
                var seenElements: [AXUIElement] = []
                var itemCount = 0
                let controlButtons = self.getWindowControlButtons(from: windowElement)
                for button in controlButtons {
                    guard itemCount < Self.maxItems else { break }
                    if !self.isDuplicate(button.axElement, in: seenElements) {
                        seenElements.append(button.axElement)
                        continuation.yield(button)
                        itemCount += 1
                        // Yield to allow UI updates
                        await Task.yield()
                    }
                }


                // Crawl window elements with streaming
//                let windowTitle = AccessibilityHelper.getTitle(windowElement) ?? app.localizedName ?? "Window"
                await self.crawlWindowInElementStreaming(
                    windowElement,
//                    path: [windowTitle],
                    depth: 0,
                    itemCount: &itemCount,
                    seenElements: &seenElements,
                    continuation: continuation
                )

                // Check for open menu (popup/select menus)
//                let pid = app.processIdentifier
//                if let openMenu = self.getOpenMenuForApp(pid: pid) {
//                    await self.crawlOpenMenuStreaming(
//                        openMenu,
//                        itemCount: &itemCount,
//                        seenElements: &seenElements,
//                        continuation: continuation
//                    )
//                }

                continuation.finish()
            }
        }
    }

    /// Checks if an element is a duplicate.
    private func isDuplicate(_ element: AXUIElement, in seenElements: [AXUIElement]) -> Bool {
        return seenElements.contains { existing in
            CFEqual(existing, element)
        }
    }

    /// Recursively crawls an element for actionable window items, yielding results via continuation.
    private func crawlWindowInElementStreaming(
        _ element: AXUIElement,
//        path: [String],
        depth: Int,
        itemCount: inout Int,
        seenElements: inout [AXUIElement],
        continuation: AsyncThrowingStream<HintTarget, Error>.Continuation
    ) async {
//        print("path: \(path)")
        // Prevent infinite recursion and enforce item limit
        guard depth < cachedMaxDepth, itemCount < Self.maxItems else { return }

        // Check for cancellation
        if Task.isCancelled { return }

        // Get children
        let children = AccessibilityHelper.getChildren(element)

        for child in children {
            guard itemCount < Self.maxItems else { break }
            if Task.isCancelled { return }

            // Get role
            guard let role = AccessibilityHelper.getRole(child) else { continue }

            // Check if this is an actionable item
//            var pathForChildren = path
            if Self.itemRoles.contains(role) {
                let canAct = canPerformAction(on: child)
                if canAct {
//                    if isSectionHeader(child, role: role) {
//                        continue
//                    }

                    // Check for duplicates
                    if !isDuplicate(child, in: seenElements) {
                        seenElements.append(child)
                        let isEnabled = AccessibilityHelper.getIsEnabled(child)

                        let target = HintTarget(
                            nativeTitle: "",
                            axElement: child,
                            isEnabled: isEnabled
                        )
                        continuation.yield(target)
                        itemCount += 1
                        // Yield to allow UI updates
                        await Task.yield()
                    }
                }
            }

//            // Recurse into containers or elements with children
//            let hasChildElements = hasChildren(child)
//            let isLeafItem = (role == "AXCheckBox" || role == "AXSwitch" || role == "AXTextField") ||
//            ((role == "AXPopUpButton" || role == "AXMenuButton" || role == "AXComboBox") && !hasChildElements)
//
//            if !isLeafItem && (Self.containerRoles.contains(role) || hasChildElements) {
//                await crawlWindowInElementStreaming(
//                    child,
//                    depth: depth + 1,
//                    itemCount: &itemCount,
//                    seenElements: &seenElements,
//                    continuation: continuation
//                )
//            }
            
//            if hasChildElements(child) {
                await crawlWindowInElementStreaming(
                    child,
                    depth: depth + 1,
                    itemCount: &itemCount,
                    seenElements: &seenElements,
                    continuation: continuation
                )
//            }
        }
    }

    /// Removes duplicate items based on their AXUIElement reference.
    ///
    /// Since `HintTarget.id` is derived from the AXUIElement reference,
    /// we compare AXUIElement references to detect true duplicates.
    /// Two targets pointing to the same AXUIElement are considered duplicates.
    private func deduplicateItems(_ items: [HintTarget]) -> [HintTarget] {
        var seenElements: [AXUIElement] = []
        var uniqueItems: [HintTarget] = []

        for item in items {
            // Check if we've already seen this AXUIElement
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

    // MARK: - Private Methods

    /// Gets the frontmost application, excluding Portal.
    private func getFrontmostApp() -> NSRunningApplication? {
        let workspace = NSWorkspace.shared
        let apps = workspace.runningApplications
        let portalBundleID = Bundle.main.bundleIdentifier

        // First try the frontmost application
        if let frontmost = workspace.frontmostApplication,
           frontmost.bundleIdentifier != portalBundleID,
           frontmost.activationPolicy == .regular {
            return frontmost
        }

        // Fallback: find any regular app that's not Portal
        return apps.first {
            $0.bundleIdentifier != portalBundleID &&
            $0.activationPolicy == .regular &&
            $0.isActive
        }
    }

    /// Gets window control buttons (close, minimize, zoom, fullscreen) from a window.
    ///
    /// These buttons are special macOS system UI elements that need to be fetched
    /// directly from the window using dedicated attributes rather than through
    /// normal child element traversal.
    ///
    /// - Parameter window: The window element to get control buttons from.
    /// - Returns: An array of HintTargets for the available control buttons.
    private func getWindowControlButtons(from window: AXUIElement) -> [HintTarget] {
        var buttons: [HintTarget] = []

        let buttonAttributes: [(String, String)] = [
            (kAXCloseButtonAttribute, "Close"),
            (kAXMinimizeButtonAttribute, "Minimize"),
            (kAXZoomButtonAttribute, "Zoom"),
            (kAXFullScreenButtonAttribute, "Full Screen")
        ]

        for (attribute, title) in buttonAttributes {
            var buttonRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, attribute as CFString, &buttonRef) == .success,
               let button = buttonRef {
                // Note: kAXCloseButtonAttribute and related window control attributes
                // always return AXUIElement type when copy succeeds.
                // swiftlint:disable:next force_cast
                let axButton = button as! AXUIElement
                // Only add if frame can be retrieved (with fallback)
                if AccessibilityHelper.getFrameWithFallback(axButton) != nil {
                    let isEnabled = AccessibilityHelper.getIsEnabled(axButton)
                    buttons.append(HintTarget(
                        nativeTitle: title,
                        axElement: axButton,
                        isEnabled: isEnabled
                    ))
                }
            }
        }

        return buttons
    }

    /// Detects an open AXMenu for the given app pid using the SystemWide focused element.
    ///
    /// Some popup/select menus are not exposed under `kAXWindowsAttribute` of the app.
    /// This fallback finds the focused UI element and walks up parents to locate an AXMenu.
    private func getOpenMenuForApp(pid: pid_t) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else {
            return nil
        }

        // swiftlint:disable:next force_cast
        var current: AXUIElement? = focused as! AXUIElement
        var depth = 0

        while let element = current, depth < cachedMaxDepth {
            depth += 1

            // Note: For some system popups (e.g., System Settings select menus),
            // the focused UI element may not have the same pid as the target app.
            // We still traverse parents to find an AXMenu, but we'll validate at the end.
            var elementPid: pid_t = 0
            AXUIElementGetPid(element, &elementPid)
#if DEBUG
            let role = AccessibilityHelper.getRole(element) ?? "unknown"
            logger.debug("SystemWide focus chain depth=\(depth) role=\(role) pid=\(elementPid)")
#endif

            if let role = AccessibilityHelper.getRole(element), role == "AXMenu" {
                // Prefer menus that belong to the target pid, but allow mismatches when
                // the popup is hosted by a helper/system process.
                var menuPid: pid_t = 0
                AXUIElementGetPid(element, &menuPid)
#if DEBUG
                logger.debug("Found AXMenu in focus chain (menuPid=\(menuPid), targetPid=\(pid))")
#endif
                return element
            }

            // Walk up to parent
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentRef) == .success,
                  let parent = parentRef else {
                return nil
            }
            // swiftlint:disable:next force_cast
            current = parent as! AXUIElement
        }

        return nil
    }

    /// Crawls menu items from an already detected open AXMenu element.
    ///
    /// This intentionally treats AXMenuItem as actionable even if action names are not readable.
    private func crawlOpenMenu(_ menu: AXUIElement, itemCount: inout Int) -> [HintTarget] {
        var results: [HintTarget] = []

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menu, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return results
        }

        for child in children {
            guard itemCount < Self.maxItems else { break }

            guard let role = AccessibilityHelper.getRole(child) else { continue }

            if role == "AXMenuItem" {
                // Priority: title > label > description > value > help
                let title = AccessibilityHelper.getAttributeValueAsString(child, attribute: kAXTitleAttribute)
                let label = AccessibilityHelper.getAttributeValueAsString(child, attribute: "AXLabel")
                let desc = AccessibilityHelper.getAttributeValueAsString(child, attribute: kAXDescriptionAttribute)
                let value = AccessibilityHelper.getAttributeValueAsString(child, attribute: kAXValueAttribute)
                let help = AccessibilityHelper.getAttributeValueAsString(child, attribute: kAXHelpAttribute)

                var displayTitle: String? = nil
                if let t = title, !t.isEmpty { displayTitle = t }
                else if let l = label, !l.isEmpty { displayTitle = l }
                else if let d = desc, !d.isEmpty { displayTitle = d }
                else if let v = value, !v.isEmpty { displayTitle = v }
                else if let h = help, !h.isEmpty { displayTitle = h }

                if let itemTitle = displayTitle, !itemTitle.isEmpty {
                    let isEnabled = AccessibilityHelper.getIsEnabled(child)
                    results.append(HintTarget(nativeTitle: itemTitle, axElement: child, isEnabled: isEnabled))
                    itemCount += 1
                }

                // Some menus can be nested; recurse into children to find deeper AXMenuItem.
                if hasChildren(child) {
                    results.append(contentsOf: crawlNestedMenuItems(in: child, itemCount: &itemCount, depth: 1))
                }
            } else if role == "AXMenu" {
                results.append(contentsOf: crawlOpenMenu(child, itemCount: &itemCount))
            } else if hasChildren(child) {
                results.append(contentsOf: crawlNestedMenuItems(in: child, itemCount: &itemCount, depth: 1))
            }
        }

        return results
    }

    private func crawlNestedMenuItems(in element: AXUIElement, itemCount: inout Int, depth: Int) -> [HintTarget] {
        guard depth < cachedMaxDepth, itemCount < Self.maxItems else { return [] }
        var results: [HintTarget] = []

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return results
        }

        for child in children {
            guard itemCount < Self.maxItems else { break }
            if let role = AccessibilityHelper.getRole(child), role == "AXMenuItem" {
                // Priority: title > label > description > value > help
                let title = AccessibilityHelper.getAttributeValueAsString(child, attribute: kAXTitleAttribute)
                let label = AccessibilityHelper.getAttributeValueAsString(child, attribute: "AXLabel")
                let desc = AccessibilityHelper.getAttributeValueAsString(child, attribute: kAXDescriptionAttribute)
                let value = AccessibilityHelper.getAttributeValueAsString(child, attribute: kAXValueAttribute)
                let help = AccessibilityHelper.getAttributeValueAsString(child, attribute: kAXHelpAttribute)

                var displayTitle: String? = nil
                if let t = title, !t.isEmpty { displayTitle = t }
                else if let l = label, !l.isEmpty { displayTitle = l }
                else if let d = desc, !d.isEmpty { displayTitle = d }
                else if let v = value, !v.isEmpty { displayTitle = v }
                else if let h = help, !h.isEmpty { displayTitle = h }

                if let itemTitle = displayTitle, !itemTitle.isEmpty {
                    let isEnabled = AccessibilityHelper.getIsEnabled(child)
                    results.append(HintTarget(nativeTitle: itemTitle, axElement: child, isEnabled: isEnabled))
                    itemCount += 1
                }
            }

            if hasChildren(child) {
                results.append(contentsOf: crawlNestedMenuItems(in: child, itemCount: &itemCount, depth: depth + 1))
            }
        }

        return results
    }
    
    /// Checks if an element has children.
    private func hasChildren(_ element: AXUIElement) -> Bool {
        return !getChildren(element).isEmpty
    }

    /// Gets children of an element.
    private func getChildren(_ element: AXUIElement) -> [AXUIElement] {
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            return children
        }
        return []
    }

    /// Checks if we can perform an action on this element.
    private func canPerformAction(on element: AXUIElement) -> Bool {
        var actionsRef: CFArray?
        guard AXUIElementCopyActionNames(element, &actionsRef) == .success,
              let actions = actionsRef as? [String] else {
            return false
        }

        // Check for press, select, or show UI action
        return actions.contains(kAXPressAction as String) ||
        actions.contains("AXSelect") ||
        actions.contains("AXConfirm") ||
        actions.contains("AXShowDefaultUI") ||
        // Common for popup/select menus
        actions.contains("AXPick") ||
        // For sliders and incrementors (#132)
        actions.contains("AXIncrement") ||
        actions.contains("AXDecrement")
    }

    /// Checks if an element is a section header that should be excluded.
    ///
    /// Section headers are elements that:
    /// - Are AXRow/AXOutlineRow with disclosure level 0 AND have a disclosure indicator
    ///   (expandable section headers like "Library", "Store", "Playlists")
    /// - Are standalone AXStaticText not inside interactive containers
    ///
    /// Navigation items at disclosure level 0 WITHOUT disclosure indicators
    /// (like "Search", "Home", "Radio") are NOT section headers and should be included.
    ///
    /// - Parameters:
    ///   - element: The element to check.
    ///   - role: The element's role.
    /// - Returns: `true` if this is a section header that should be excluded.
    private func isSectionHeader(_ element: AXUIElement, role: String) -> Bool {
        // Get element title for debugging
        let elementTitle = AccessibilityHelper.getTitle(element) ?? AccessibilityHelper.getValue(element)
        ?? "unknown"

        // For AXRow and AXOutlineRow, check if it's an expandable section header
        if role == "AXRow" || role == "AXOutlineRow" {
            // Check disclosure level - section headers typically have level 0
            var disclosureLevelRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                element,
                "AXDisclosureLevel" as CFString,
                &disclosureLevelRef
            ) == .success, let level = disclosureLevelRef as? Int {
                // Level 0 could be either a section header or a navigation item
                // Section headers have a disclosure triangle (AXDisclosing attribute or disclosure child)
                if level == 0 {
                    // Check for AXDisclosing attribute VALUE (true = expanded section header)
                    // Navigation items may have AXDisclosing = false or no children
                    var disclosingRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(
                        element,
                        "AXDisclosing" as CFString,
                        &disclosingRef
                    ) == .success, let isDisclosing = disclosingRef as? Bool {
//#if DEBUG
//                        logger.debug("isSectionHeader: '\(elementTitle)' level 0, AXDisclosing=\(isDisclosing)")
//#endif
                        // Only skip if actually expanded (showing children)
                        if isDisclosing {
                            return true
                        }
                        // AXDisclosing = false means it's a navigation item, not a section header
                        return false
                    }

                    // Also check for disclosure triangle child element
                    if hasDisclosureTriangle(element) {
//#if DEBUG
//                        logger.debug("isSectionHeader: '\(elementTitle)' level 0 with disclosure triangle -> section header")
//#endif
                        return true
                    }

//#if DEBUG
//                    logger.debug("isSectionHeader: '\(elementTitle)' level 0 without disclosure -> navigation item")
//#endif
                    return false
                }

#if DEBUG
                logger.debug("isSectionHeader: '\(elementTitle)' level \(level) -> not a section header")
#endif
            }
            return false
        }

        // For AXStaticText, check if parent is interactive
        if role == "AXStaticText" {
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                element,
                kAXParentAttribute as CFString,
                &parentRef
            ) == .success else {
                return true
            }

            // swiftlint:disable:next force_cast
            let parent = parentRef as! AXUIElement
            guard let parentRole = AccessibilityHelper.getRole(parent) else {
                return true
            }

            let interactiveParentRoles: Set<String> = [
                "AXRow", "AXCell", "AXOutlineRow", "AXButton"
            ]
            return !interactiveParentRoles.contains(parentRole)
        }

        return false
    }

    /// Checks if an element has a disclosure triangle child.
    ///
    /// Disclosure triangles are used to expand/collapse section headers.
    private func hasDisclosureTriangle(_ element: AXUIElement) -> Bool {
        let children = getChildren(element)
        for child in children {
            if let role = AccessibilityHelper.getRole(child) {
                // Check for disclosure triangle or button that controls disclosure
                if role == "AXDisclosureTriangle" || role == "AXOutline" {
                    return true
                }
                // Also check subrole
                var subroleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXSubroleAttribute as CFString, &subroleRef) == .success,
                   let subrole = subroleRef as? String,
                   subrole == "AXOutlineRowDisclosure" || subrole == "AXDisclosureTriangle" {
                    return true
                }
            }
        }
        return false
    }

    /// Gets the title from a row element by searching its children.
    private func getTitleFromRowChildren(_ element: AXUIElement) -> String? {
        let children = getChildren(element)

        // First pass: Look for AXStaticText elements which usually contain the actual label
        for child in children {
            let role = AccessibilityHelper.getRole(child)

            if role == "AXStaticText" {
                if let value = AccessibilityHelper.getValue(child), !value.isEmpty {
                    return value
                }
                if let title = AccessibilityHelper.getTitle(child), !title.isEmpty {
                    return title
                }
            }

            // Check grandchildren for AXStaticText
            let grandchildren = getChildren(child)
            for grandchild in grandchildren {
                let grandRole = AccessibilityHelper.getRole(grandchild)
                if grandRole == "AXStaticText" {
                    if let value = AccessibilityHelper.getValue(grandchild), !value.isEmpty {
                        return value
                    }
                    if let title = AccessibilityHelper.getTitle(grandchild), !title.isEmpty {
                        return title
                    }
                }
            }
        }

        // Second pass: Look for AXCell with title
        for child in children {
            let role = AccessibilityHelper.getRole(child)
            if role == "AXCell" {
                if let title = AccessibilityHelper.getTitle(child), !title.isEmpty {
                    return title
                }
            }
        }

        // Third pass: Fallback to any title/value
        for child in children {
            if let title = AccessibilityHelper.getTitle(child), !title.isEmpty {
                return title
            }
            if let value = AccessibilityHelper.getValue(child)
                , !value.isEmpty {
                return value
            }

            let grandchildren = getChildren(child)
            for grandchild in grandchildren {
                if let title = AccessibilityHelper.getTitle(grandchild), !title.isEmpty {
                    return title
                }
                if let value = AccessibilityHelper.getValue(grandchild)
                    , !value.isEmpty {
                    return value
                }
            }
        }

        return nil
    }

    /// Gets the title from sibling elements (for toggle switches and checkboxes).
    ///
    /// AXSwitch and AXCheckBox elements typically don't have their own title attribute.
    /// Instead, the label is in a sibling AXStaticText element within the same parent container.
    ///
    /// For elements inside AXCell/AXGroup containers (e.g., System Settings tables),
    /// the label may be in a sibling AXCell's child element rather than a direct sibling.
    /// In this case, we also search the grandparent's children (uncle elements).
    ///
    /// - Parameter element: The AXSwitch or AXCheckBox element.
    /// - Returns: The title found in a sibling element, or nil if not found.
    private func getTitleFromSiblings(_ element: AXUIElement) -> String? {
        // Get the parent element
        var parentRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentRef) == .success else {
            return nil
        }
        // swiftlint:disable:next force_cast
        let parent = parentRef as! AXUIElement

        // Get parent's role for grandparent search decision
        let parentRole = AccessibilityHelper.getRole(parent)

        // Get sibling elements (children of parent)
        let siblings = getChildren(parent)

        // Look for AXStaticText siblings that contain the label
        for sibling in siblings {
            // Skip the element itself
            if CFEqual(sibling, element) {
                continue
            }

            if let role = AccessibilityHelper.getRole(sibling), role == "AXStaticText" {
                if let value = AccessibilityHelper.getValue(sibling), !value.isEmpty {
                    return value
                }
                if let title = AccessibilityHelper.getTitle(sibling), !title.isEmpty {
                    return title
                }
            }
        }

        // If parent is AXCell or AXGroup, look in grandparent's children (uncle elements).
        // This handles cases like System Settings tables where:
        // AXRow > AXCell (label) > AXStaticText "App Store"
        // AXRow > AXCell (toggle) > AXSwitch  <- we're here
        if parentRole == "AXCell" || parentRole == "AXGroup" {
            if let uncleTitle = AccessibilityHelper.getTitleFromUncles(parent: parent, skipElement: parent) {
                return uncleTitle
            }
        }

        // Fallback: try the parent's description
        if let desc = AccessibilityHelper.getAttributeValueAsString(parent, attribute: kAXDescriptionAttribute), !desc.isEmpty {
            return desc
        }

        return nil
    }

    //    /// Gets the role attribute from an accessibility element.
    //    private func getRole(from element: AXUIElement) -> String? {
    //        var roleRef: CFTypeRef?
    //        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success else {
    //            return nil
    //        }
    //        return roleRef as? String
    //    }

    /// Gets the placeholder value attribute from an accessibility element.
    /// This is typically used for text fields to show hint text (e.g., "Find in Songs").
    private func getPlaceholderValue(from element: AXUIElement) -> String? {
        var placeholderRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXPlaceholderValue" as CFString, &placeholderRef) == .success else {
            return nil
        }
        return placeholderRef as? String
    }

//    /// Gets the enabled state from an element.
//    private func getIsEnabled(from element: AXUIElement) -> Bool {
//        var enabledRef: CFTypeRef?
//        guard AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabledRef) == .success else {
//            return true  // Default to enabled if we can't determine
//        }
//        return (enabledRef as? Bool) ?? true
//    }

    /// Gets a display name for a container element to include in item paths.
    ///
    /// This ensures that items with the same title but in different containers
    /// (e.g., "iTunes Store" in sidebar vs toolbar) have unique paths and IDs.
    ///
    /// - Parameters:
    ///   - element: The container element.
    ///   - role: The container's accessibility role.
    /// - Returns: A name for the container, or nil if no name should be added.
    private func getContainerName(_ element: AXUIElement, role: String) -> String? {
        // First, try the element's description (e.g., "Sidebar" for AXOutline)
        if let desc = AccessibilityHelper.getAttributeValueAsString(element, attribute: kAXDescriptionAttribute), !desc.isEmpty {
            return desc
        }

        // Fall back to default names for certain container types
        switch role {
        case "AXToolbar":
            return "Toolbar"
        default:
            return nil
        }
    }
}

// MARK: - Backward Compatibility

/// Type alias for backward compatibility with existing code.
typealias WindowCrawler = NativeAppCrawler

/// Type alias for backward compatibility with existing error handling.
typealias WindowCrawlerError = NativeAppCrawlerError
