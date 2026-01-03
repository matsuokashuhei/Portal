//
//  WindowCrawler.swift
//  Portal
//
//  Created by Claude Code on 2026/01/02.
//

import ApplicationServices
import AppKit

/// Error types for window crawling operations.
enum WindowCrawlerError: Error, LocalizedError {
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

/// Result of window crawling operation.
///
/// Contains the crawled items and metadata about the crawl context.
struct WindowCrawlResult {
    /// The crawled menu items.
    let items: [MenuItem]

    /// Whether a popup menu was detected.
    ///
    /// When `true`, the items are popup menu items (AXMenuItem) and should not
    /// be filtered by window bounds, as popup menus can extend beyond the main window.
    let isPopupMenu: Bool
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
/// Unlike MenuCrawler, no caching is used because window content can change
/// more frequently (e.g., when navigating folders).
@MainActor
final class WindowCrawler {
    /// Maximum depth for recursive traversal to prevent infinite loops.
    /// Increased to 20 to support Electron apps (Slack, VS Code) where AXWebArea
    /// content can be nested 15+ levels deep.
    private static let maxDepth = 20

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
        "AXMenu",
        "AXMenuBar",
        // Electron/Chromium web content area
        "AXWebArea",
        "AXTabGroup"
    ]

    /// Accessibility roles for actionable items we can interact with.
    private static let itemRoles: Set<String> = [
        "AXRow",
        "AXCell",
        "AXOutlineRow",
        "AXStaticText",
        "AXButton",
        "AXRadioButton",
        "AXMenuItem",
        "AXCheckBox",
        "AXMenuButton",
        "AXSwitch",
        "AXPopUpButton",
        "AXComboBox",
        "AXTextField"
    ]

    #if DEBUG
    /// Tracks all roles encountered during crawling for analysis.
    private var roleCounts: [String: Int] = [:]
    /// Tracks roles that are not in itemRoles or containerRoles.
    private var unknownRoles: Set<String> = []
    /// Tracks elements without titles for debugging.
    private var elementsWithoutTitle: [(role: String, actions: [String])] = []
    #endif

    /// Crawls window elements from the application's windows.
    ///
    /// If AXMenuItem elements are found in the hierarchy (indicating a popup menu is open),
    /// only those menu items are returned. Otherwise, crawls the main window normally.
    ///
    /// - Parameter app: The application to crawl window elements from.
    /// - Returns: A `WindowCrawlResult` containing the items and whether a popup menu was detected.
    /// - Throws: WindowCrawlerError if crawling fails.
    func crawlWindowElements(_ app: NSRunningApplication) async throws -> WindowCrawlResult {
        guard AccessibilityService.isGranted else {
            throw WindowCrawlerError.accessibilityNotGranted
        }

        #if DEBUG
        // Reset debug tracking
        roleCounts = [:]
        unknownRoles = []
        elementsWithoutTitle = []
        print("[WindowCrawler] ========== START CRAWL ==========")
        print("[WindowCrawler] App: \(app.localizedName ?? "Unknown") (Bundle: \(app.bundleIdentifier ?? "unknown"))")
        #endif

        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)

        var itemCount = 0

        // Get main window
        var mainWindowRef: CFTypeRef?
        let mainWindowResult = AXUIElementCopyAttributeValue(
            axApp,
            kAXMainWindowAttribute as CFString,
            &mainWindowRef
        )

        guard mainWindowResult == .success, let mainWindow = mainWindowRef else {
            throw WindowCrawlerError.mainWindowNotAccessible
        }

        // swiftlint:disable:next force_cast
        let windowElement = mainWindow as! AXUIElement
        let windowTitle = getTitle(from: windowElement) ?? app.localizedName ?? "Window"

        // First, check for AXMenuItem elements in the hierarchy
        // If found, a popup menu is open - return only those items
        let menuItems = collectMenuItems(in: windowElement, path: [windowTitle, "Menu"], itemCount: &itemCount)
        if !menuItems.isEmpty {
            #if DEBUG
            print("[WindowCrawler] Popup menu detected - returning \(menuItems.count) menu items only")
            #endif
            return WindowCrawlResult(items: deduplicateItems(menuItems), isPopupMenu: true)
        }

        // No popup menu - crawl main window normally
        #if DEBUG
        print("[WindowCrawler] Crawling main window: '\(windowTitle)'")
        #endif

        let allItems = crawlWindowInElement(windowElement, path: [windowTitle], depth: 0, itemCount: &itemCount)

        #if DEBUG
        printDebugSummary(totalItems: allItems.count)
        #endif

        return WindowCrawlResult(items: deduplicateItems(allItems), isPopupMenu: false)
    }

    #if DEBUG
    /// Recursively prints element tree for debugging.
    private func debugPrintElementTree(_ element: AXUIElement, indent: Int, maxDepth: Int) {
        guard indent < maxDepth else { return }

        let children = getChildren(element)
        let prefix = String(repeating: "  ", count: indent)

        for (idx, child) in children.prefix(30).enumerated() {
            guard let role = getRole(from: child) else { continue }
            let title = getTitle(from: child) ?? ""
            let desc = getDescription(from: child) ?? ""
            let value = getValue(from: child) ?? ""
            let help = getHelp(from: child) ?? ""

            // Check if actionable
            var actionsRef: CFArray?
            var actions: [String] = []
            if AXUIElementCopyActionNames(child, &actionsRef) == .success,
               let arr = actionsRef as? [String] {
                actions = arr
            }
            let actionStr = actions.isEmpty ? "" : " actions=[\(actions.joined(separator: ","))]"

            let displayInfo = [title, desc, value, help].filter { !$0.isEmpty }.joined(separator: "|")
            print("[WindowCrawler] 🌐 \(prefix)[\(idx)] \(role) '\(displayInfo.prefix(60))'\(actionStr)")

            // Recurse into children
            debugPrintElementTree(child, indent: indent + 1, maxDepth: maxDepth)
        }
    }

    /// Prints a summary of the crawl for debugging Electron app compatibility.
    private func printDebugSummary(totalItems: Int) {
        print("[WindowCrawler] ========== CRAWL SUMMARY ==========")
        print("[WindowCrawler] Total items found: \(totalItems)")

        // Print role counts sorted by frequency
        print("[WindowCrawler] --- Role Counts (sorted by frequency) ---")
        let sortedRoles = roleCounts.sorted { $0.value > $1.value }
        for (role, count) in sortedRoles {
            let isKnown = Self.itemRoles.contains(role) || Self.containerRoles.contains(role)
            let marker = isKnown ? "✓" : "?"
            print("[WindowCrawler]   \(marker) \(role): \(count)")
        }

        // Print unknown roles (potential candidates for Electron support)
        if !unknownRoles.isEmpty {
            print("[WindowCrawler] --- Unknown Roles (not in itemRoles/containerRoles) ---")
            for role in unknownRoles.sorted() {
                print("[WindowCrawler]   ⚠️ \(role)")
            }
        }

        // Print elements without titles
        if !elementsWithoutTitle.isEmpty {
            print("[WindowCrawler] --- Elements Without Title (\(elementsWithoutTitle.count) total) ---")
            // Group by role
            var byRole: [String: Int] = [:]
            for elem in elementsWithoutTitle {
                byRole[elem.role, default: 0] += 1
            }
            for (role, count) in byRole.sorted(by: { $0.value > $1.value }) {
                print("[WindowCrawler]   \(role): \(count) elements without title")
            }
        }

        print("[WindowCrawler] ========== END CRAWL ==========")
    }
    #endif

    /// Collects all AXMenuItem elements from the hierarchy.
    ///
    /// This method recursively searches for AXMenuItem elements, which indicate
    /// that a popup/context menu is currently open. Some apps (like Music) don't
    /// wrap popup menus in an AXMenu element, so we detect by finding AXMenuItem directly.
    ///
    /// - Parameters:
    ///   - element: The root element to search from.
    ///   - path: The current path for item identification.
    ///   - itemCount: Counter for total items found.
    ///   - depth: Current recursion depth (default 0).
    /// - Returns: Array of MenuItem objects representing popup menu items.
    private func collectMenuItems(
        in element: AXUIElement,
        path: [String],
        itemCount: inout Int,
        depth: Int = 0
    ) -> [MenuItem] {
        guard depth < Self.maxDepth, itemCount < Self.maxItems else {
            return []
        }

        var items: [MenuItem] = []

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return items
        }

        for child in children {
            guard itemCount < Self.maxItems else { break }

            guard let role = getRole(from: child) else { continue }

            // Found an AXMenuItem - check if it's inside a proper AXMenu context
            // This distinguishes real popup menus from AXMenuItem elements used elsewhere in the UI
            // (e.g., sidebar navigation items that may have AXMenuItem role)
            if role == "AXMenuItem" {
                // Only treat as popup menu item if parent is AXMenu
                var parentRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXParentAttribute as CFString, &parentRef) == .success {
                    // swiftlint:disable:next force_cast
                    let parent = parentRef as! AXUIElement
                    if let parentRole = getRole(from: parent), parentRole == "AXMenu" {
                        let title = getTitle(from: child)
                        let desc = getDescription(from: child)
                        var displayTitle: String? = nil
                        if let t = title, !t.isEmpty { displayTitle = t }
                        else if let d = desc, !d.isEmpty { displayTitle = d }

                        if let itemTitle = displayTitle, !itemTitle.isEmpty {
                            let isEnabled = getIsEnabled(from: child)
                            let currentPath = path + [itemTitle]

                            #if DEBUG
                            print("[WindowCrawler] Found popup menu item: '\(itemTitle)'")
                            #endif

                            let menuItem = MenuItem(
                                title: itemTitle,
                                path: currentPath,
                                keyboardShortcut: nil,
                                axElement: child,
                                isEnabled: isEnabled,
                                type: .window
                            )
                            items.append(menuItem)
                            itemCount += 1
                        }
                    }
                }
            }

            // Recursively search in all containers
            if Self.containerRoles.contains(role) || hasChildren(child) {
                let subItems = collectMenuItems(in: child, path: path, itemCount: &itemCount, depth: depth + 1)
                items.append(contentsOf: subItems)
            }
        }

        return items
    }

    /// Removes duplicate items based on their AXUIElement reference.
    ///
    /// Since MenuItem.id is now UUID-based (to support items with the same title),
    /// we need to compare AXUIElement references to detect true duplicates.
    /// Two MenuItems pointing to the same AXUIElement are considered duplicates.
    private func deduplicateItems(_ items: [MenuItem]) -> [MenuItem] {
        var seenElements: [AXUIElement] = []
        var uniqueItems: [MenuItem] = []

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

    /// Gets frame from an element (for comparison purposes).
    private func getFrame(from element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero

        guard let posValue = positionRef,
              CFGetTypeID(posValue) == AXValueGetTypeID(),
              AXValueGetValue(posValue as! AXValue, .cgPoint, &position),
              let sizeValue = sizeRef,
              CFGetTypeID(sizeValue) == AXValueGetTypeID(),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    /// Crawls window elements from the currently active application.
    ///
    /// - Important: This method may fail to find a non-Portal application if Portal itself
    ///   is the only regular application running, or if Portal becomes frontmost before
    ///   this method is called. Callers should capture the target application reference
    ///   BEFORE showing the panel (as done in `AppDelegate.handleHotkeyPressed()`) and
    ///   use `crawlWindowElements(_:)` instead when possible.
    ///
    /// - Returns: A `WindowCrawlResult` containing the items and whether a popup menu was detected.
    /// - Throws: WindowCrawlerError if crawling fails.
    func crawlActiveApplicationWindow() async throws -> WindowCrawlResult {
        guard AccessibilityService.isGranted else {
            throw WindowCrawlerError.accessibilityNotGranted
        }

        guard let app = getFrontmostApp() else {
            throw WindowCrawlerError.noActiveApplication
        }

        return try await crawlWindowElements(app)
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

    /// Recursively crawls an element for actionable window items.
    private func crawlWindowInElement(
        _ element: AXUIElement,
        path: [String],
        depth: Int,
        itemCount: inout Int
    ) -> [MenuItem] {
        // Prevent infinite recursion and enforce item limit
        guard depth < Self.maxDepth, itemCount < Self.maxItems else {
            return []
        }

        var items: [MenuItem] = []

        // Get children
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return items
        }

        for child in children {
            guard itemCount < Self.maxItems else { break }

            // Get role
            var roleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
                  let role = roleRef as? String else {
                continue
            }

            #if DEBUG
            // Track role counts for analysis
            roleCounts[role, default: 0] += 1

            // Track unknown roles
            if !Self.itemRoles.contains(role) && !Self.containerRoles.contains(role) {
                unknownRoles.insert(role)
            }

            // Deep debug for AXWebArea - show its children structure recursively
            if role == "AXWebArea" {
                print("[WindowCrawler] 🌐 AXWebArea found at depth \(depth), exploring deeply (maxDepth: 12)...")
                debugPrintElementTree(child, indent: 0, maxDepth: 12)
            }
            #endif

            // Get title or description - try multiple attributes for buttons
            // Use first non-empty value (empty string is different from nil)
            let title = getTitle(from: child)
            let desc = getDescription(from: child)
            let value = getValue(from: child)
            let help = getHelp(from: child)
            var displayTitle: String? = nil
            if let t = title, !t.isEmpty { displayTitle = t }
            else if let d = desc, !d.isEmpty { displayTitle = d }
            else if let v = value, !v.isEmpty { displayTitle = v }
            else if let h = help, !h.isEmpty { displayTitle = h }

            #if DEBUG
            // Log all elements at depth 1-2 to see contents
            if depth <= 2 {
                let pathStr = path.joined(separator: " > ")
                print("[WindowCrawler] depth=\(depth) role=\(role) title='\(title ?? "")' desc='\(desc ?? "")' help='\(help ?? "")' path=\(pathStr)")
            }
            #endif

            // For row-type elements without a direct title, look in children
            if (displayTitle == nil || displayTitle?.isEmpty == true) &&
               (role == "AXRow" || role == "AXOutlineRow" || role == "AXCell") {
                displayTitle = getTitleFromRowChildren(child)
            }

            // For toggle switches and checkboxes, look in sibling elements for labels
            // These elements typically have their label in a sibling AXStaticText element
            if (displayTitle == nil || displayTitle?.isEmpty == true) &&
               (role == "AXSwitch" || role == "AXCheckBox") {
                displayTitle = getTitleFromSiblings(child)
            }

            // For text fields, try placeholder value first (e.g., "Find in Songs"),
            // then fall back to sibling labels
            if (displayTitle == nil || displayTitle?.isEmpty == true) && role == "AXTextField" {
                displayTitle = getPlaceholderValue(from: child)
                if displayTitle == nil || displayTitle?.isEmpty == true {
                    displayTitle = getTitleFromSiblings(child)
                }
            }

            // Check if this is an actionable item
            var pathForChildren = path
            if Self.itemRoles.contains(role) {
                let canAct = canPerformAction(on: child)

                #if DEBUG
                // Track elements without title for debugging
                if (displayTitle == nil || displayTitle?.isEmpty == true) && canAct {
                    var actionsRef: CFArray?
                    var actions: [String] = []
                    if AXUIElementCopyActionNames(child, &actionsRef) == .success,
                       let actionsArray = actionsRef as? [String] {
                        actions = actionsArray
                    }
                    elementsWithoutTitle.append((role: role, actions: actions))
                }
                #endif

                if let itemTitle = displayTitle, !itemTitle.isEmpty, canAct {
                    // Skip section headers (like "Library", "Store", "Playlists" in Music app)
                    // These have AXPress action but don't actually do anything
                    if isSectionHeader(child, role: role) {
                        #if DEBUG
                        print("[WindowCrawler] Skipping section header: '\(itemTitle)' (role: \(role))")
                        #endif
                        continue
                    }

                    #if DEBUG
                    print("[WindowCrawler] Adding item: '\(itemTitle)' (role: \(role))")
                    #endif

                    let isEnabled = getIsEnabled(from: child)
                    let currentPath = path + [itemTitle]
                    pathForChildren = currentPath

                    let menuItem = MenuItem(
                        title: itemTitle,
                        path: currentPath,
                        keyboardShortcut: nil,
                        axElement: child,
                        isEnabled: isEnabled,
                        type: .window
                    )
                    items.append(menuItem)
                    itemCount += 1
                }
            }

            // Recurse into containers or elements with children
            // Skip recursion for actionable leaf items (they shouldn't have crawlable children)
            let isLeafItem = role == "AXMenuButton" || role == "AXCheckBox" ||
                             role == "AXSwitch" || role == "AXPopUpButton" ||
                             role == "AXComboBox" || role == "AXTextField"
            if !isLeafItem && (Self.containerRoles.contains(role) || hasChildren(child)) {
                // For containers, include the container name in the path to differentiate
                // items with the same title in different locations (e.g., "iTunes Store" in
                // both sidebar and toolbar)
                var pathForContainer = pathForChildren
                if Self.containerRoles.contains(role) {
                    if let containerName = getContainerName(child, role: role), !containerName.isEmpty {
                        pathForContainer = pathForChildren + [containerName]
                    }
                }
                let subItems = crawlWindowInElement(child, path: pathForContainer, depth: depth + 1, itemCount: &itemCount)
                items.append(contentsOf: subItems)
            }
        }

        return items
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
               actions.contains("AXShowDefaultUI")
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
        let elementTitle = getTitle(from: element) ?? getValue(from: element) ?? "unknown"

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
                        #if DEBUG
                        print("[WindowCrawler] isSectionHeader: '\(elementTitle)' level 0, AXDisclosing=\(isDisclosing)")
                        #endif
                        // Only skip if actually expanded (showing children)
                        if isDisclosing {
                            return true
                        }
                        // AXDisclosing = false means it's a navigation item, not a section header
                        return false
                    }

                    // Also check for disclosure triangle child element
                    if hasDisclosureTriangle(element) {
                        #if DEBUG
                        print("[WindowCrawler] isSectionHeader: '\(elementTitle)' level 0 with disclosure triangle → section header")
                        #endif
                        return true
                    }

                    #if DEBUG
                    print("[WindowCrawler] isSectionHeader: '\(elementTitle)' level 0 without disclosure → navigation item")
                    #endif
                    return false
                }

                #if DEBUG
                print("[WindowCrawler] isSectionHeader: '\(elementTitle)' level \(level) → not a section header")
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
            guard let parentRole = getRole(from: parent) else {
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
            if let role = getRole(from: child) {
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

    /// Gets the title attribute from an accessibility element.
    private func getTitle(from element: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success else {
            return nil
        }
        return titleRef as? String
    }

    /// Gets the title from a row element by searching its children.
    private func getTitleFromRowChildren(_ element: AXUIElement) -> String? {
        let children = getChildren(element)

        // First pass: Look for AXStaticText elements which usually contain the actual label
        for child in children {
            let role = getRole(from: child)

            if role == "AXStaticText" {
                if let value = getValue(from: child), !value.isEmpty {
                    return value
                }
                if let title = getTitle(from: child), !title.isEmpty {
                    return title
                }
            }

            // Check grandchildren for AXStaticText
            let grandchildren = getChildren(child)
            for grandchild in grandchildren {
                let grandRole = getRole(from: grandchild)
                if grandRole == "AXStaticText" {
                    if let value = getValue(from: grandchild), !value.isEmpty {
                        return value
                    }
                    if let title = getTitle(from: grandchild), !title.isEmpty {
                        return title
                    }
                }
            }
        }

        // Second pass: Look for AXCell with title
        for child in children {
            let role = getRole(from: child)
            if role == "AXCell" {
                if let title = getTitle(from: child), !title.isEmpty {
                    return title
                }
            }
        }

        // Third pass: Fallback to any title/value
        for child in children {
            if let title = getTitle(from: child), !title.isEmpty {
                return title
            }
            if let value = getValue(from: child), !value.isEmpty {
                return value
            }

            let grandchildren = getChildren(child)
            for grandchild in grandchildren {
                if let title = getTitle(from: grandchild), !title.isEmpty {
                    return title
                }
                if let value = getValue(from: grandchild), !value.isEmpty {
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

        // Get sibling elements (children of parent)
        let siblings = getChildren(parent)

        // Look for AXStaticText siblings that contain the label
        for sibling in siblings {
            // Skip the element itself
            if CFEqual(sibling, element) {
                continue
            }

            if let role = getRole(from: sibling), role == "AXStaticText" {
                if let value = getValue(from: sibling), !value.isEmpty {
                    return value
                }
                if let title = getTitle(from: sibling), !title.isEmpty {
                    return title
                }
            }
        }

        // Fallback: try the parent's description
        if let desc = getDescription(from: parent), !desc.isEmpty {
            return desc
        }

        return nil
    }

    /// Gets the role attribute from an accessibility element.
    private func getRole(from element: AXUIElement) -> String? {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success else {
            return nil
        }
        return roleRef as? String
    }

    /// Gets the description attribute from an accessibility element.
    private func getDescription(from element: AXUIElement) -> String? {
        var descRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef) == .success else {
            return nil
        }
        return descRef as? String
    }

    /// Gets the value attribute from an accessibility element.
    private func getValue(from element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success else {
            return nil
        }
        return valueRef as? String
    }

    /// Gets the help attribute from an accessibility element.
    /// This is often used for button tooltips/accessibility labels.
    private func getHelp(from element: AXUIElement) -> String? {
        var helpRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXHelpAttribute as CFString, &helpRef) == .success else {
            return nil
        }
        return helpRef as? String
    }

    /// Gets the placeholder value attribute from an accessibility element.
    /// This is typically used for text fields to show hint text (e.g., "Find in Songs").
    private func getPlaceholderValue(from element: AXUIElement) -> String? {
        var placeholderRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXPlaceholderValue" as CFString, &placeholderRef) == .success else {
            return nil
        }
        return placeholderRef as? String
    }

    /// Gets the enabled state from an element.
    private func getIsEnabled(from element: AXUIElement) -> Bool {
        var enabledRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabledRef) == .success else {
            return true  // Default to enabled if we can't determine
        }
        return (enabledRef as? Bool) ?? true
    }

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
        if let desc = getDescription(from: element), !desc.isEmpty {
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
