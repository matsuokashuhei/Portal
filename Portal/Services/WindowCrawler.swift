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
            let title = getTitle(from: child) ?? getDescription(from: child)

            // Check if this is an actionable sidebar item
            if Self.sidebarItemRoles.contains(role) {
                if let title = title, !title.isEmpty, canPerformAction(on: child) {
                    let isEnabled = getIsEnabled(from: child)
                    let currentPath = path + [title]

                    let menuItem = MenuItem(
                        title: title,
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
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            return !children.isEmpty
        }
        return false
    }

    /// Checks if we can perform an action on this element.
    private func canPerformAction(on element: AXUIElement) -> Bool {
        var actionsRef: CFArray?
        guard AXUIElementCopyActionNames(element, &actionsRef) == .success,
              let actions = actionsRef as? [String] else {
            return false
        }

        // Check for press or select action
        return actions.contains(kAXPressAction as String) ||
               actions.contains("AXSelect") ||
               actions.contains("AXConfirm")
    }

    /// Gets the title attribute from an accessibility element.
    private func getTitle(from element: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success else {
            return nil
        }
        return titleRef as? String
    }

    /// Gets the description attribute from an accessibility element.
    private func getDescription(from element: AXUIElement) -> String? {
        var descRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef) == .success else {
            return nil
        }
        return descRef as? String
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
