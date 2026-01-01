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
            return "Portal needs Accessibility permission to read menus. Please enable access in System Settings > Privacy & Security > Accessibility."
        case .noActiveApplication:
            return "No active application found. Click on an app window to make it active, then try again."
        case .menuBarNotAccessible:
            return "Unable to access this app's menu bar. The app may not have a menu bar, may be in full-screen mode, or may have quit."
        }
    }
}

/// Service for crawling application menu bars using Accessibility API.
/// Must run on main thread as Accessibility API may trigger menu modifications.
@MainActor
final class MenuCrawler {
    /// Default cache duration in seconds.
    /// Note: This short duration is a trade-off between performance and freshness.
    /// Menu items may become stale if the target application modifies its menus
    /// dynamically (e.g., enabling/disabling items based on context). For most
    /// applications, 0.5 seconds provides a good balance. Future improvements could
    /// include observing NSMenu notifications for cache invalidation.
    private static let defaultCacheDuration: TimeInterval = 0.5

    /// Cache duration for Finder.
    /// Finder's menus change more dynamically than typical apps (based on selection,
    /// system state, etc.), so we use a much shorter cache duration to reduce the
    /// risk of stale AXUIElement references causing unintended actions.
    private static let finderCacheDuration: TimeInterval = 0.1

    /// Finder's bundle identifier.
    private static let finderBundleIdentifier = "com.apple.finder"

    /// Cached menu items with timestamp, process identifier, and bundle identifier.
    private var cache: (items: [MenuItem], timestamp: Date, pid: pid_t, bundleId: String?)?

    /// Crawls the menu bar of the specified application.
    /// - Parameter app: The application to crawl menus from.
    /// - Returns: Array of menu items found in the application.
    /// - Throws: MenuCrawlerError if crawling fails.
    func crawlApplication(_ app: NSRunningApplication) async throws -> [MenuItem] {
        guard AccessibilityService.isGranted else {
            throw MenuCrawlerError.accessibilityNotGranted
        }

        let pid = app.processIdentifier
        let bundleId = app.bundleIdentifier
        let cacheDuration = getCacheDuration(for: bundleId)

        // Check cache validity
        if let cached = cache,
           cached.pid == pid,
           cached.bundleId == bundleId,
           Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.items
        }

        // Crawl menu bar
        let items = try crawlMenuBar(for: app)

        // Update cache
        cache = (items: items, timestamp: Date(), pid: pid, bundleId: bundleId)

        return items
    }

    /// Returns the appropriate cache duration for the given application.
    private func getCacheDuration(for bundleId: String?) -> TimeInterval {
        bundleId == Self.finderBundleIdentifier ? Self.finderCacheDuration : Self.defaultCacheDuration
    }

    /// Crawls the menu bar of the currently active application.
    ///
    /// - Important: This method may fail to find a non-Portal application if Portal itself
    ///   is the only regular application running, or if Portal becomes frontmost before
    ///   this method is called. Callers should capture the target application reference
    ///   BEFORE showing the panel (as done in `AppDelegate.handleHotkeyPressed()`) and
    ///   use `crawlApplication(_:)` instead when possible.
    ///
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

    /// Invalidates any cached menu items.
    ///
    /// Call this when the UI that displays menu data (e.g., a panel or popover)
    /// is hidden or closed, or whenever you know the target application's menus
    /// may have changed and you want to force a fresh crawl on the next request.
    ///
    /// Note: The cache already has a short TTL (0.5 seconds), so calling this
    /// is only necessary if you need immediate invalidation before the TTL expires.
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

        // The Accessibility API guarantees that kAXMenuBarAttribute returns an AXUIElement
        // when AXUIElementCopyAttributeValue returns .success. The force cast is safe here
        // because CoreFoundation types cannot use conditional casting (as? always succeeds).
        // swiftlint:disable:next force_cast
        let menuBarElement = menuBar as! AXUIElement

        // Get menu bar items (top-level menus like File, Edit, etc.)
        var menuBarItemsRef: CFTypeRef?
        let itemsResult = AXUIElementCopyAttributeValue(menuBarElement, kAXChildrenAttribute as CFString, &menuBarItemsRef)

        guard itemsResult == .success,
              let menuBarItems = menuBarItemsRef as? [AXUIElement] else {
            return []
        }

        var allMenuItems: [MenuItem] = []

        // Iterate through each top-level menu
        for (index, menuBarItem) in menuBarItems.enumerated() {
            let menuTitle = getTitle(from: menuBarItem) ?? ""

            // Skip Apple menu (always first menu bar item) and empty titles
            if index == 0 || menuTitle.isEmpty {
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
            if AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &submenuRef) == .success,
               let submenus = submenuRef as? [AXUIElement],
               !submenus.isEmpty {
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

    /// Carbon-style modifier flags as reported by kAXMenuItemCmdModifiersAttribute.
    ///
    /// These values match the legacy Carbon Event Manager constants:
    ///   - shiftKey   = 1
    ///   - optionKey  = 2
    ///   - controlKey = 4
    ///   - noCommand  = 8 (when set, suppresses the implicit Command key)
    ///
    /// This mapping is based on documented Carbon constants. If a future macOS version
    /// changes these semantics, these bit values may need to be updated.
    private enum ModifierFlags {
        static let shift: Int = 1
        static let option: Int = 2
        static let control: Int = 4
        static let noCommand: Int = 8
    }

    /// Formats a keyboard shortcut with modifier symbols.
    private func formatShortcut(char: String, modifiers: Int) -> String {
        var result = ""

        if modifiers & ModifierFlags.control != 0 { result += "⌃" }
        if modifiers & ModifierFlags.option != 0 { result += "⌥" }
        if modifiers & ModifierFlags.shift != 0 { result += "⇧" }
        if modifiers & ModifierFlags.noCommand == 0 { result += "⌘" }

        // Only uppercase single alphabetic characters; special keys (arrows, function keys)
        // may use multi-character strings that shouldn't be uppercased
        if char.count == 1, char.first?.isLetter == true {
            result += char.uppercased()
        } else {
            result += char
        }

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
