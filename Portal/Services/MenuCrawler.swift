//
//  MenuCrawler.swift
//  Portal
//
//  Created by Claude Code on 2025/12/31.
//

import ApplicationServices
import AppKit

/// Error types for menu crawling operations.
enum MenuCrawlerError: Error, LocalizedError {
    case accessibilityNotGranted
    case noActiveApplication
    case menuBarNotAccessible

    var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            return "Accessibility permission is not granted"
        case .noActiveApplication:
            return "No active application found"
        case .menuBarNotAccessible:
            return "Menu bar is not accessible"
        }
    }
}

/// Service for crawling application menu bars using Accessibility API.
actor MenuCrawler {
    /// Cache duration in seconds.
    private static let cacheDuration: TimeInterval = 0.5

    /// Cached menu items with timestamp.
    private var cache: (items: [MenuItem], timestamp: Date, bundleID: String)?

    /// Crawls the menu bar of the specified application.
    /// - Parameter app: The application to crawl menus from.
    /// - Returns: Array of menu items found in the application.
    /// - Throws: MenuCrawlerError if crawling fails.
    func crawlApplication(_ app: NSRunningApplication) async throws -> [MenuItem] {
        guard AccessibilityService.isGranted else {
            throw MenuCrawlerError.accessibilityNotGranted
        }

        let bundleID = app.bundleIdentifier ?? ""

        // Check cache validity
        if let cached = cache,
           cached.bundleID == bundleID,
           Date().timeIntervalSince(cached.timestamp) < Self.cacheDuration {
            return cached.items
        }

        // Crawl menu bar
        let items = try crawlMenuBar(for: app)

        // Update cache
        cache = (items: items, timestamp: Date(), bundleID: bundleID)

        return items
    }

    /// Crawls the menu bar of the currently active application.
    /// - Returns: Array of menu items found in the active application.
    /// - Throws: MenuCrawlerError if crawling fails.
    func crawlActiveApplication() async throws -> [MenuItem] {
        guard AccessibilityService.isGranted else {
            throw MenuCrawlerError.accessibilityNotGranted
        }

        // Get frontmost application (excluding Portal itself)
        guard let app = getFrontmostApp() else {
            throw MenuCrawlerError.noActiveApplication
        }

        return try await crawlApplication(app)
    }

    /// Invalidates the menu cache.
    func invalidateCache() {
        cache = nil
    }

    // MARK: - Private Methods

    /// Gets the frontmost application, excluding Portal.
    private func getFrontmostApp() -> NSRunningApplication? {
        let workspace = NSWorkspace.shared
        let apps = workspace.runningApplications

        // Find the frontmost app that is not Portal
        let portalBundleID = Bundle.main.bundleIdentifier

        // First try the activeApplication
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

    /// Crawls the menu bar of the given application.
    private func crawlMenuBar(for app: NSRunningApplication) throws -> [MenuItem] {
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)

        // Get menu bar
        var menuBarRef: CFTypeRef?
        let menuBarResult = AXUIElementCopyAttributeValue(axApp, kAXMenuBarAttribute as CFString, &menuBarRef)

        guard menuBarResult == .success, let menuBar = menuBarRef else {
            throw MenuCrawlerError.menuBarNotAccessible
        }

        // Get menu bar items (top-level menus like File, Edit, etc.)
        var menuBarItemsRef: CFTypeRef?
        let itemsResult = AXUIElementCopyAttributeValue(menuBar as! AXUIElement, kAXChildrenAttribute as CFString, &menuBarItemsRef)

        guard itemsResult == .success,
              let menuBarItems = menuBarItemsRef as? [AXUIElement] else {
            return []
        }

        var allMenuItems: [MenuItem] = []

        // Iterate through each top-level menu
        for menuBarItem in menuBarItems {
            let menuTitle = getTitle(from: menuBarItem) ?? ""

            // Skip Apple menu and empty titles
            if menuTitle.isEmpty || menuTitle == "Apple" {
                continue
            }

            // Get submenu
            var submenuRef: CFTypeRef?
            let submenuResult = AXUIElementCopyAttributeValue(menuBarItem, kAXChildrenAttribute as CFString, &submenuRef)

            if submenuResult == .success, let submenus = submenuRef as? [AXUIElement] {
                for submenu in submenus {
                    let items = crawlMenu(submenu, path: [menuTitle])
                    allMenuItems.append(contentsOf: items)
                }
            }
        }

        return allMenuItems
    }

    /// Recursively crawls a menu and its submenus.
    private func crawlMenu(_ menu: AXUIElement, path: [String]) -> [MenuItem] {
        var items: [MenuItem] = []

        // Get children (menu items)
        var childrenRef: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(menu, kAXChildrenAttribute as CFString, &childrenRef)

        guard childrenResult == .success, let children = childrenRef as? [AXUIElement] else {
            return items
        }

        for child in children {
            // Get title
            guard let title = getTitle(from: child), !title.isEmpty else {
                continue
            }

            // Skip separators
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String,
               role == "AXMenuItemSeparator" {
                continue
            }

            let currentPath = path + [title]

            // Check if this item has a submenu
            var submenuRef: CFTypeRef?
            let hasSubmenu = AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &submenuRef) == .success &&
                             (submenuRef as? [AXUIElement])?.isEmpty == false

            if hasSubmenu, let submenus = submenuRef as? [AXUIElement] {
                // Recurse into submenu
                for submenu in submenus {
                    let subItems = crawlMenu(submenu, path: currentPath)
                    items.append(contentsOf: subItems)
                }
            } else {
                // Leaf menu item - add it
                let shortcut = getKeyboardShortcut(from: child)
                let isEnabled = getIsEnabled(from: child)

                let menuItem = MenuItem(
                    title: title,
                    path: currentPath,
                    keyboardShortcut: shortcut,
                    axElement: child,
                    isEnabled: isEnabled
                )
                items.append(menuItem)
            }
        }

        return items
    }

    /// Gets the title attribute from an accessibility element.
    private func getTitle(from element: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success else {
            return nil
        }
        return titleRef as? String
    }

    /// Gets the keyboard shortcut from a menu item element.
    private func getKeyboardShortcut(from element: AXUIElement) -> String? {
        // Get the command character
        var cmdCharRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMenuItemCmdCharAttribute as CFString, &cmdCharRef) == .success,
              let cmdChar = cmdCharRef as? String,
              !cmdChar.isEmpty else {
            return nil
        }

        // Get modifier keys
        var modifiersRef: CFTypeRef?
        var modifiers: Int = 0
        if AXUIElementCopyAttributeValue(element, kAXMenuItemCmdModifiersAttribute as CFString, &modifiersRef) == .success,
           let modValue = modifiersRef as? Int {
            modifiers = modValue
        }

        return formatShortcut(char: cmdChar, modifiers: modifiers)
    }

    /// Formats a keyboard shortcut with modifier symbols.
    private func formatShortcut(char: String, modifiers: Int) -> String {
        var result = ""

        // kAXMenuItemCmdModifiersAttribute uses Carbon modifier flags:
        // Shift = 1, Option = 2, Control = 4, Command = 0 (implicit)
        // Note: Command is implicit unless cmdVirtualKey is set

        if modifiers & 4 != 0 { result += "⌃" }  // Control
        if modifiers & 2 != 0 { result += "⌥" }  // Option
        if modifiers & 1 != 0 { result += "⇧" }  // Shift
        result += "⌘"  // Command is always implied for menu shortcuts

        result += char.uppercased()

        return result
    }

    /// Gets the enabled state from a menu item element.
    private func getIsEnabled(from element: AXUIElement) -> Bool {
        var enabledRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabledRef) == .success else {
            return true  // Default to enabled if we can't determine
        }
        return (enabledRef as? Bool) ?? true
    }
}
