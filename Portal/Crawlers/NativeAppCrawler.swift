//
//  NativeAppCrawler.swift
//  Portal
//
//  Created by Claude Code on 2026/01/02.
//  Renamed from WindowCrawler on 2026/01/10.
//

import ApplicationServices
import AppKit

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
@MainActor
final class NativeAppCrawler: ElementCrawler {
    // MARK: - ElementCrawler Protocol

    /// Native macOS apps use Accessibility API coordinates (top-left origin).
    let coordinateSystem: HintCoordinateSystem = .native

    // MARK: - Constants

    /// Maximum depth for recursive traversal to prevent infinite loops.
    /// Increased from 10 to 15 to support deeply nested elements like
    /// AXCheckBox inside AXCell inside AXRow in System Settings tables.
    private static let maxDepth = 15

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

    /// Determines whether this crawler can handle the specified application.
    ///
    /// NativeAppCrawler handles all applications by default.
    /// More specialized crawlers (like ElectronCrawler) can override this
    /// to claim specific applications.
    ///
    /// - Parameter app: The application to check.
    /// - Returns: Always `true` for NativeAppCrawler.
    func canHandle(_ app: NSRunningApplication) -> Bool {
        return true
    }

    /// Crawls UI elements from the specified application.
    ///
    /// - Parameter app: The application to crawl elements from.
    /// - Returns: An array of discovered hint targets.
    /// - Throws: NativeAppCrawlerError if crawling fails.
    func crawlElements(_ app: NSRunningApplication) async throws -> [HintTarget] {
        guard AccessibilityService.isGranted else {
            throw NativeAppCrawlerError.accessibilityNotGranted
        }

        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)

        var itemCount = 0

        // Crawl all windows (main window + popup windows like select menus)
        // so that popup/select menu items can also be targeted by Hint Mode.
        let windows = getAllWindows(from: axApp)
        guard !windows.isEmpty else {
            throw NativeAppCrawlerError.mainWindowNotAccessible
        }

        var allItems: [HintTarget] = []
        for windowElement in windows {
            // Get window control buttons (close, minimize, zoom, fullscreen)
            let controlButtons = getWindowControlButtons(from: windowElement)
            #if DEBUG
            if !controlButtons.isEmpty {
                print("[NativeAppCrawler] Found \(controlButtons.count) window control buttons")
            }
            #endif
            allItems.append(contentsOf: controlButtons)
            itemCount += controlButtons.count

            let windowTitle = getTitle(from: windowElement) ?? app.localizedName ?? "Window"
            #if DEBUG
            print("[NativeAppCrawler] Crawling window: '\(windowTitle)'")
            #endif
            allItems.append(contentsOf: crawlWindowInElement(windowElement, path: [windowTitle], depth: 0, itemCount: &itemCount))
        }

        // If a popup/select menu is open, it may not appear under the app's window tree.
        // In that case, detect it via the system-wide focused element and crawl the AXMenu directly.
        if let openMenu = getOpenMenuForApp(pid: pid) {
            #if DEBUG
            print("[NativeAppCrawler] Detected open AXMenu via SystemWide for pid=\(pid)")
            #endif
            let menuItems = crawlOpenMenu(openMenu, itemCount: &itemCount)
            #if DEBUG
            print("[NativeAppCrawler] Crawled \(menuItems.count) menu items from open AXMenu")
            #endif
            allItems.append(contentsOf: menuItems)
        } else {
            #if DEBUG
            print("[NativeAppCrawler] No open AXMenu detected via SystemWide for pid=\(pid)")
            #endif
        }

        return deduplicateItems(allItems)
    }

    /// Removes duplicate items based on their AXUIElement reference.
    ///
    /// Since `HintTarget.id` is UUID-based (to support elements with the same title),
    /// we need to compare AXUIElement references to detect true duplicates.
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
    ///   use `crawlElements(_:)` instead when possible.
    ///
    /// - Returns: An array of crawled Hint Mode targets.
    /// - Throws: NativeAppCrawlerError if crawling fails.
    func crawlActiveApplicationWindow() async throws -> [HintTarget] {
        guard AccessibilityService.isGranted else {
            throw NativeAppCrawlerError.accessibilityNotGranted
        }

        guard let app = getFrontmostApp() else {
            throw NativeAppCrawlerError.noActiveApplication
        }

        return try await crawlElements(app)
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

    /// Gets all windows of the app, including focused/popup windows.
    ///
    /// Popup/select menus may appear as separate windows (sometimes focused),
    /// so we crawl both `kAXWindowsAttribute` and `kAXFocusedWindowAttribute`.
    private func getAllWindows(from axApp: AXUIElement) -> [AXUIElement] {
        var windows: [AXUIElement] = []

        // kAXWindowsAttribute
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let ws = windowsRef as? [AXUIElement] {
            windows.append(contentsOf: ws)
        }

        // kAXFocusedWindowAttribute (can include popups not present in kAXWindows)
        var focusedWindowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindowRef) == .success,
           let fw = focusedWindowRef {
            // swiftlint:disable:next force_cast
            let focused = fw as! AXUIElement
            if !windows.contains(where: { CFEqual($0, focused) }) {
                windows.append(focused)
            }
        }

        // Fallback to main window if nothing else is available
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
                // swiftlint:disable:next force_cast
                let axButton = button as! AXUIElement
                // Only add if frame can be retrieved
                if AccessibilityHelper.getFrame(axButton) != nil {
                    let isEnabled = getIsEnabled(from: axButton)
                    buttons.append(HintTarget(
                        title: title,
                        axElement: axButton,
                        isEnabled: isEnabled,
                        targetType: .native
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

        while let element = current, depth < Self.maxDepth {
            depth += 1

            // Note: For some system popups (e.g., System Settings select menus),
            // the focused UI element may not have the same pid as the target app.
            // We still traverse parents to find an AXMenu, but we'll validate at the end.
            var elementPid: pid_t = 0
            AXUIElementGetPid(element, &elementPid)
            #if DEBUG
            let role = getRole(from: element) ?? "unknown"
            print("[NativeAppCrawler] SystemWide focus chain depth=\(depth) role=\(role) pid=\(elementPid)")
            #endif

            if let role = getRole(from: element), role == "AXMenu" {
                // Prefer menus that belong to the target pid, but allow mismatches when
                // the popup is hosted by a helper/system process.
                var menuPid: pid_t = 0
                AXUIElementGetPid(element, &menuPid)
                #if DEBUG
                print("[NativeAppCrawler] Found AXMenu in focus chain (menuPid=\(menuPid), targetPid=\(pid))")
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

            guard let role = getRole(from: child) else { continue }

            if role == "AXMenuItem" {
                let title = getTitle(from: child)
                let desc = getDescription(from: child)
                let value = getValue(from: child)
                let help = getHelp(from: child)

                var displayTitle: String? = nil
                if let t = title, !t.isEmpty { displayTitle = t }
                else if let d = desc, !d.isEmpty { displayTitle = d }
                else if let v = value, !v.isEmpty { displayTitle = v }
                else if let h = help, !h.isEmpty { displayTitle = h }

                if let itemTitle = displayTitle, !itemTitle.isEmpty {
                    let isEnabled = getIsEnabled(from: child)
                    results.append(HintTarget(title: itemTitle, axElement: child, isEnabled: isEnabled, targetType: .native))
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
        guard depth < Self.maxDepth, itemCount < Self.maxItems else { return [] }
        var results: [HintTarget] = []

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return results
        }

        for child in children {
            guard itemCount < Self.maxItems else { break }
            if let role = getRole(from: child), role == "AXMenuItem" {
                let title = getTitle(from: child)
                let desc = getDescription(from: child)
                let value = getValue(from: child)
                let help = getHelp(from: child)

                var displayTitle: String? = nil
                if let t = title, !t.isEmpty { displayTitle = t }
                else if let d = desc, !d.isEmpty { displayTitle = d }
                else if let v = value, !v.isEmpty { displayTitle = v }
                else if let h = help, !h.isEmpty { displayTitle = h }

                if let itemTitle = displayTitle, !itemTitle.isEmpty {
                    let isEnabled = getIsEnabled(from: child)
                    results.append(HintTarget(title: itemTitle, axElement: child, isEnabled: isEnabled, targetType: .native))
                    itemCount += 1
                }
            }

            if hasChildren(child) {
                results.append(contentsOf: crawlNestedMenuItems(in: child, itemCount: &itemCount, depth: depth + 1))
            }
        }

        return results
    }

    /// Recursively crawls an element for actionable window items.
    private func crawlWindowInElement(
        _ element: AXUIElement,
        path: [String],
        depth: Int,
        itemCount: inout Int
    ) -> [HintTarget] {
        // Prevent infinite recursion and enforce item limit
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

            // Get role
            var roleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
                  let role = roleRef as? String else {
                continue
            }

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
                print("[NativeAppCrawler] depth=\(depth) role=\(role) title='\(title ?? "")' desc='\(desc ?? "")' help='\(help ?? "")' path=\(pathStr)")
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
                if let itemTitle = displayTitle, !itemTitle.isEmpty, canAct {
                    // Skip section headers (like "Library", "Store", "Playlists" in Music app)
                    // These have AXPress action but don't actually do anything
                    if isSectionHeader(child, role: role) {
                        #if DEBUG
                        print("[NativeAppCrawler] Skipping section header: '\(itemTitle)' (role: \(role))")
                        #endif
                        continue
                    }

                    #if DEBUG
                    print("[NativeAppCrawler] Adding item: '\(itemTitle)' (role: \(role))")
                    #endif

                    let isEnabled = getIsEnabled(from: child)
                    let currentPath = path + [itemTitle]
                    pathForChildren = currentPath

                    let target = HintTarget(
                        title: itemTitle,
                        axElement: child,
                        isEnabled: isEnabled,
                        targetType: .native
                    )
                    items.append(target)
                    itemCount += 1
                }
            }

            // Recurse into containers or elements with children.
            //
            // Most actionable controls are "leaf" items, but some (notably AXPopUpButton / AXMenuButton / AXComboBox)
            // can expose their opened menu as child elements. If they have children, we MUST crawl them to capture
            // popup/select menu options as Hint Targets.
            let hasChildElements = hasChildren(child)
            let isLeafItem = (role == "AXCheckBox" || role == "AXSwitch" || role == "AXTextField") ||
                             ((role == "AXPopUpButton" || role == "AXMenuButton" || role == "AXComboBox") && !hasChildElements)

            #if DEBUG
            if (role == "AXPopUpButton" || role == "AXMenuButton" || role == "AXComboBox"), hasChildElements {
                print("[NativeAppCrawler] Crawling children for opened control role=\(role) title='\(displayTitle ?? "")' depth=\(depth)")
            }
            #endif

            if !isLeafItem && (Self.containerRoles.contains(role) || hasChildElements) {
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
                        print("[NativeAppCrawler] isSectionHeader: '\(elementTitle)' level 0, AXDisclosing=\(isDisclosing)")
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
                        print("[NativeAppCrawler] isSectionHeader: '\(elementTitle)' level 0 with disclosure triangle → section header")
                        #endif
                        return true
                    }

                    #if DEBUG
                    print("[NativeAppCrawler] isSectionHeader: '\(elementTitle)' level 0 without disclosure → navigation item")
                    #endif
                    return false
                }

                #if DEBUG
                print("[NativeAppCrawler] isSectionHeader: '\(elementTitle)' level \(level) → not a section header")
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
        let parentRole = getRole(from: parent)

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

// MARK: - Backward Compatibility

/// Type alias for backward compatibility with existing code.
typealias WindowCrawler = NativeAppCrawler

/// Type alias for backward compatibility with existing error handling.
typealias WindowCrawlerError = NativeAppCrawlerError
