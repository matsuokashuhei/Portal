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
    private static let maxDepth = 10

    /// Maximum number of items to return (performance safeguard).
    private static let maxItems = 200

    /// Accessibility roles for container elements that should be traversed.
    private static let containerRoles: Set<String> = [
        "AXOutline",
        "AXList",
        "AXTable",
        "AXScrollArea",
        "AXSplitGroup",
        "AXGroup",
        "AXToolbar",
        "AXSegmentedControl"
    ]

    /// Accessibility roles for actionable items we can interact with.
    private static let itemRoles: Set<String> = [
        "AXRow",
        "AXCell",
        "AXOutlineRow",
        "AXStaticText",
        "AXButton",
        "AXRadioButton"
    ]

    /// Crawls window elements from the main window of the specified application.
    ///
    /// - Parameter app: The application to crawl window elements from.
    /// - Returns: Array of menu items representing window UI elements.
    /// - Throws: WindowCrawlerError if crawling fails.
    func crawlWindowElements(_ app: NSRunningApplication) async throws -> [MenuItem] {
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

        // Crawl all window elements
        var itemCount = 0
        let allItems = crawlWindowInElement(windowElement, path: [windowTitle], depth: 0, itemCount: &itemCount)

        // Deduplicate by title (same element may be reached via different paths)
        var seenTitles = Set<String>()
        var uniqueItems: [MenuItem] = []
        for item in allItems {
            if !seenTitles.contains(item.title) {
                seenTitles.insert(item.title)
                uniqueItems.append(item)
            }
        }

        return uniqueItems
    }

    /// Crawls window elements from the currently active application.
    ///
    /// - Important: This method may fail to find a non-Portal application if Portal itself
    ///   is the only regular application running, or if Portal becomes frontmost before
    ///   this method is called. Callers should capture the target application reference
    ///   BEFORE showing the panel (as done in `AppDelegate.handleHotkeyPressed()`) and
    ///   use `crawlWindowElements(_:)` instead when possible.
    ///
    /// - Returns: Array of menu items representing window UI elements.
    /// - Throws: WindowCrawlerError if crawling fails.
    func crawlActiveApplicationWindow() async throws -> [MenuItem] {
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

            // Get title or description
            let title = getTitle(from: child)
            let desc = getDescription(from: child)
            let value = getValue(from: child)
            var displayTitle = title ?? desc ?? value

            // For row-type elements without a direct title, look in children
            if (displayTitle == nil || displayTitle?.isEmpty == true) &&
               (role == "AXRow" || role == "AXOutlineRow" || role == "AXCell") {
                displayTitle = getTitleFromRowChildren(child)
            }

            // Check if this is an actionable item
            var pathForChildren = path
            if Self.itemRoles.contains(role) {
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
                        type: .window
                    )
                    items.append(menuItem)
                    itemCount += 1
                }
            }

            // Recurse into containers or elements with children
            if Self.containerRoles.contains(role) || hasChildren(child) {
                let subItems = crawlWindowInElement(child, path: pathForChildren, depth: depth + 1, itemCount: &itemCount)
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
}
