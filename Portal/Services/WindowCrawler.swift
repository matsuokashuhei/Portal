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
    /// Maximum depth for recursive sidebar traversal to prevent infinite loops.
    private static let maxDepth = 10

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
        let portalBundleID = Bundle.main.bundleIdentifier

        if let frontmost = workspace.frontmostApplication,
           frontmost.bundleIdentifier != portalBundleID,
           frontmost.activationPolicy == .regular {
            return frontmost
        }

        return nil
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
            if Self.sidebarItemRoles.contains(role) {
                let canAct = canPerformAction(on: child)
                if let itemTitle = displayTitle, !itemTitle.isEmpty, canAct {
                    let isEnabled = getIsEnabled(from: child)
                    let currentPath = path + [itemTitle]

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

            // Check if this is a container we should recurse into
            if Self.sidebarContainerRoles.contains(role) {
                // For containers, recurse to find items inside
                let subItems = crawlSidebarInElement(child, path: path, depth: depth + 1)
                items.append(contentsOf: subItems)
            } else if hasChildren(child) {
                // Also recurse into elements with children (might contain sidebar)
                let subItems = crawlSidebarInElement(child, path: path, depth: depth + 1)
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

    /// Gets the identifier attribute from an accessibility element.
    private func getIdentifier(from element: AXUIElement) -> String? {
        var idRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &idRef) == .success else {
            return nil
        }
        return idRef as? String
    }

    /// Gets the list of actions available on an element.
    private func getActions(from element: AXUIElement) -> [String] {
        var actionsRef: CFArray?
        guard AXUIElementCopyActionNames(element, &actionsRef) == .success,
              let actions = actionsRef as? [String] else {
            return []
        }
        return actions
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
