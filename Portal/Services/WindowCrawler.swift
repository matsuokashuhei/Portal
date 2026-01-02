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

/// Service for crawling window UI elements (sidebars) using Accessibility API.
///
/// This service crawls sidebar navigation items (AXSourceList, AXOutline, AXRow)
/// from an application's main window.
///
/// ## Supported Applications
/// - Apple Music (Library, Playlists)
/// - Finder (Favorites, Locations)
/// - Notes (Folders)
/// - Mail (Mailboxes)
///
/// ## Performance
/// Window crawling typically takes 50-200ms depending on sidebar depth.
/// Unlike MenuCrawler, no caching is used because sidebar content can change
/// more frequently (e.g., when navigating folders).
@MainActor
final class WindowCrawler {
    /// Maximum depth for recursive traversal to prevent infinite loops.
    private static let maxDepth = 10

    /// Maximum number of content items to return (performance safeguard).
    private static let maxContentItems = 100

    /// Accessibility roles that indicate sidebar containers.
    private static let sidebarContainerRoles: Set<String> = [
        "AXOutline",
        "AXList",
        "AXTable",
        "AXScrollArea",
        "AXSplitGroup",
        "AXGroup"
    ]

    /// Accessibility roles that indicate sidebar items we can interact with.
    private static let sidebarItemRoles: Set<String> = [
        "AXRow",
        "AXCell",
        "AXOutlineRow",
        "AXStaticText"
    ]

    /// Accessibility roles for content container elements.
    private static let contentContainerRoles: Set<String> = [
        "AXGroup",
        "AXScrollArea",
        "AXSplitGroup",
        "AXList",
        "AXTable"
    ]

    /// Accessibility roles for actionable content items.
    private static let contentItemRoles: Set<String> = [
        "AXButton",
        "AXRow",
        "AXCell",
        "AXStaticText",
        "AXGroup"
    ]

    /// Roles that are known sidebar containers and should be skipped during content crawling.
    private static let sidebarSkipRoles: Set<String> = [
        "AXOutline",
        "AXSourceList"
    ]

    /// Crawls sidebar elements from the main window of the specified application.
    ///
    /// - Parameter app: The application to crawl sidebar elements from.
    /// - Returns: Array of menu items representing sidebar elements.
    /// - Throws: WindowCrawlerError if crawling fails.
    func crawlSidebarElements(_ app: NSRunningApplication) async throws -> [MenuItem] {
        guard AccessibilityService.isGranted else {
            throw WindowCrawlerError.accessibilityNotGranted
        }

        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)

        // Get main window
        var mainWindowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            axApp,
            kAXMainWindowAttribute as CFString,
            &mainWindowRef
        )

        guard result == .success, let mainWindow = mainWindowRef else {
            throw WindowCrawlerError.mainWindowNotAccessible
        }

        // The Accessibility API guarantees that kAXMainWindowAttribute returns an AXUIElement
        // when AXUIElementCopyAttributeValue returns .success. The force cast is safe here
        // because CoreFoundation types cannot use conditional casting (as? always succeeds).
        // swiftlint:disable:next force_cast
        let windowElement = mainWindow as! AXUIElement

        // Get window title for path prefix
        let windowTitle = getTitle(from: windowElement) ?? app.localizedName ?? "Window"

        // Crawl sidebar elements
        return crawlSidebarInElement(windowElement, path: [windowTitle], depth: 0)
    }

    /// Crawls the currently active application's sidebar.
    ///
    /// - Important: This method may fail to find a non-Portal application if Portal itself
    ///   is the only regular application running, or if Portal becomes frontmost before
    ///   this method is called. Callers should capture the target application reference
    ///   BEFORE showing the panel (as done in `AppDelegate.handleHotkeyPressed()`) and
    ///   use `crawlSidebarElements(_:)` instead when possible.
    ///
    /// - Returns: Array of menu items representing sidebar elements.
    /// - Throws: WindowCrawlerError if crawling fails.
    func crawlActiveApplication() async throws -> [MenuItem] {
        guard AccessibilityService.isGranted else {
            throw WindowCrawlerError.accessibilityNotGranted
        }

        guard let app = getFrontmostApp() else {
            throw WindowCrawlerError.noActiveApplication
        }

        return try await crawlSidebarElements(app)
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

    /// Recursively crawls an element for sidebar items.
    private func crawlSidebarInElement(_ element: AXUIElement, path: [String], depth: Int) -> [MenuItem] {
        // Prevent infinite recursion
        guard depth < Self.maxDepth else {
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
            // Get role
            var roleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
                  let role = roleRef as? String else {
                continue
            }

            // Get title or description
            // For AXRow elements, the title is often in child elements
            let title = getTitle(from: child)
            let desc = getDescription(from: child)
            let value = getValue(from: child)
            var displayTitle = title ?? desc ?? value

            // For row-type elements without a direct title, look in children
            if (displayTitle == nil || displayTitle?.isEmpty == true) &&
               (role == "AXRow" || role == "AXOutlineRow") {
                displayTitle = getTitleFromRowChildren(child)
            }

            // Check if this is an actionable sidebar item
            var pathForChildren = path
            if Self.sidebarItemRoles.contains(role) {
                let canAct = canPerformAction(on: child)
                if let itemTitle = displayTitle, !itemTitle.isEmpty, canAct {
                    let isEnabled = getIsEnabled(from: child)
                    let currentPath = path + [itemTitle]
                    pathForChildren = currentPath

                    let menuItem = MenuItem(
                        title: itemTitle,
                        path: currentPath,
                        keyboardShortcut: nil,
                        axElement: child,
                        isEnabled: isEnabled,
                        type: .sidebar
                    )
                    items.append(menuItem)
                }
            }

            // Recurse into containers or elements with children to find nested sidebar items.
            // Note: An element may be both an actionable item AND contain children (e.g., expandable
            // sidebar rows). This is intentional - we add the parent as an actionable item above,
            // then explore its children for additional items. If the parent was actionable, children
            // inherit its path so the hierarchy is correctly reflected (e.g., "Music → Library").
            if Self.sidebarContainerRoles.contains(role) {
                let subItems = crawlSidebarInElement(child, path: pathForChildren, depth: depth + 1)
                items.append(contentsOf: subItems)
            } else if hasChildren(child) {
                let subItems = crawlSidebarInElement(child, path: pathForChildren, depth: depth + 1)
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
        // AXShowDefaultUI is used by Apple Music sidebar items
        return actions.contains(kAXPressAction as String) ||
               actions.contains("AXSelect") ||
               actions.contains("AXConfirm") ||
               actions.contains("AXShowDefaultUI")
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
    /// AXRow elements often don't have a title directly; the title is in a child AXStaticText or AXCell.
    /// Priority: AXStaticText value/title > AXCell title > other attributes
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

        // Third pass: Fallback to any title/value (but not description, which is often icon name)
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

    /// Gets the enabled state from an element.
    private func getIsEnabled(from element: AXUIElement) -> Bool {
        var enabledRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabledRef) == .success else {
            return true  // Default to enabled if we can't determine
        }
        return (enabledRef as? Bool) ?? true
    }

    // MARK: - Position and Size

    /// Gets the position (top-left corner) of an accessibility element in screen coordinates.
    /// Returns nil if position cannot be determined.
    func getPosition(from element: AXUIElement) -> CGPoint? {
        var positionRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionRef
        ) == .success else {
            return nil
        }

        var point = CGPoint.zero
        guard let value = positionRef,
              CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetValue(value as! AXValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    /// Gets the size of an accessibility element.
    /// Returns nil if size cannot be determined.
    func getSize(from element: AXUIElement) -> CGSize? {
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeRef
        ) == .success else {
            return nil
        }

        var size = CGSize.zero
        guard let value = sizeRef,
              CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetValue(value as! AXValue, .cgSize, &size) else {
            return nil
        }
        return size
    }

    /// Gets the frame (position + size) of an accessibility element in screen coordinates.
    /// Returns nil if frame cannot be determined.
    func getFrame(from element: AXUIElement) -> CGRect? {
        guard let position = getPosition(from: element),
              let size = getSize(from: element) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    /// Gets the window ID from a window element by matching position and size.
    ///
    /// Since `_AXUIElementGetWindow` is a private API, we use CGWindowListCopyWindowInfo
    /// to find the window by matching its frame with the accessibility element's frame.
    ///
    /// - Parameter windowElement: The accessibility element representing a window
    /// - Returns: The CGWindowID if found, nil otherwise
    func getWindowID(from windowElement: AXUIElement) -> CGWindowID? {
        guard let windowFrame = getFrame(from: windowElement) else {
            return nil
        }

        // Get list of all windows
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        // Find window matching the frame (with small tolerance for rounding)
        for windowInfo in windowList {
            guard let bounds = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID else {
                continue
            }

            let windowBounds = CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )

            // Check if frames match (with 2px tolerance for rounding differences)
            if abs(windowFrame.origin.x - windowBounds.origin.x) < 2 &&
               abs(windowFrame.origin.y - windowBounds.origin.y) < 2 &&
               abs(windowFrame.width - windowBounds.width) < 2 &&
               abs(windowFrame.height - windowBounds.height) < 2 {
                return windowID
            }
        }

        return nil
    }

    // MARK: - Content Crawling

    /// Crawls content elements from the main window of the specified application.
    ///
    /// - Parameters:
    ///   - app: The application to crawl content elements from.
    ///   - excludePaths: Set of item IDs to exclude (typically sidebar item IDs for deduplication).
    /// - Returns: Array of menu items representing content elements.
    /// - Throws: WindowCrawlerError if crawling fails.
    func crawlContentElements(_ app: NSRunningApplication, excludePaths: Set<String> = []) async throws -> [MenuItem] {
        guard AccessibilityService.isGranted else {
            throw WindowCrawlerError.accessibilityNotGranted
        }

        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)

        var mainWindowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            axApp,
            kAXMainWindowAttribute as CFString,
            &mainWindowRef
        )

        guard result == .success, let mainWindow = mainWindowRef else {
            throw WindowCrawlerError.mainWindowNotAccessible
        }

        // swiftlint:disable:next force_cast
        let windowElement = mainWindow as! AXUIElement
        let windowTitle = getTitle(from: windowElement) ?? app.localizedName ?? "Window"

        var itemCount = 0
        return crawlContentInElement(
            windowElement,
            path: [windowTitle],
            depth: 0,
            excludePaths: excludePaths,
            itemCount: &itemCount
        )
    }

    /// Crawls content from the currently active application's window.
    ///
    /// - Parameter excludePaths: Set of item IDs to exclude (typically sidebar item IDs).
    /// - Returns: Array of menu items representing content elements.
    /// - Throws: WindowCrawlerError if crawling fails.
    func crawlActiveApplicationContent(excludePaths: Set<String> = []) async throws -> [MenuItem] {
        guard AccessibilityService.isGranted else {
            throw WindowCrawlerError.accessibilityNotGranted
        }

        guard let app = getFrontmostApp() else {
            throw WindowCrawlerError.noActiveApplication
        }

        return try await crawlContentElements(app, excludePaths: excludePaths)
    }

    /// Recursively crawls an element for content items, excluding known sidebar elements.
    private func crawlContentInElement(
        _ element: AXUIElement,
        path: [String],
        depth: Int,
        excludePaths: Set<String>,
        itemCount: inout Int
    ) -> [MenuItem] {
        // Prevent infinite recursion and enforce item limit
        guard depth < Self.maxDepth, itemCount < Self.maxContentItems else {
            return []
        }

        var items: [MenuItem] = []
        let children = getChildren(element)

        for child in children {
            guard itemCount < Self.maxContentItems else { break }

            guard let role = getRole(from: child) else { continue }

            // Skip known sidebar containers to avoid duplication
            if Self.sidebarSkipRoles.contains(role) {
                continue
            }

            let title = getTitle(from: child)
            let desc = getDescription(from: child)
            let value = getValue(from: child)
            var displayTitle = title ?? desc ?? value

            // For row-type elements, look in children for title
            if (displayTitle == nil || displayTitle?.isEmpty == true) &&
               (role == "AXRow" || role == "AXCell") {
                displayTitle = getTitleFromRowChildren(child)
            }

            var pathForChildren = path

            // Check if this is an actionable content item
            if Self.contentItemRoles.contains(role) {
                let canAct = canPerformAction(on: child)
                if let itemTitle = displayTitle, !itemTitle.isEmpty, canAct {
                    let currentPath = path + [itemTitle]
                    // Update path for children regardless of whether this item is added
                    // This ensures correct path hierarchy for nested elements
                    pathForChildren = currentPath

                    // Check if there's a sidebar item with the same path and skip to avoid duplicates
                    let sidebarId = CommandType.sidebar.rawValue + "\0" + currentPath.joined(separator: "\0")
                    if !excludePaths.contains(sidebarId) {
                        let isEnabled = getIsEnabled(from: child)

                        let menuItem = MenuItem(
                            title: itemTitle,
                            path: currentPath,
                            keyboardShortcut: nil,
                            axElement: child,
                            isEnabled: isEnabled,
                            type: .content
                        )
                        items.append(menuItem)
                        itemCount += 1
                    }
                }
            }

            // Recurse into containers
            if Self.contentContainerRoles.contains(role) || hasChildren(child) {
                let subItems = crawlContentInElement(
                    child,
                    path: pathForChildren,
                    depth: depth + 1,
                    excludePaths: excludePaths,
                    itemCount: &itemCount
                )
                items.append(contentsOf: subItems)
            }
        }

        return items
    }
}
