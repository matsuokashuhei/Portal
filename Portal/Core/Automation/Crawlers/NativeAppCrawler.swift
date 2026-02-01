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
    
    // MARK: - ElementCrawler Protocol
    
    /// Crawls UI elements from the specified application as an async stream.
    ///
    /// This method yields elements as they are discovered, enabling progressive
    /// rendering of hint labels. Use this for better responsiveness when crawling
    /// applications with many UI elements.
    ///
    /// - Parameter app: The application to crawl elements from.
    /// - Returns: An async stream of discovered hint targets.
    func crawlElementsStream(_ window: Window) -> AsyncThrowingStream<HintTarget, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                guard AccessibilityService.isGranted else {
                    continuation.finish(throwing: NativeAppCrawlerError.accessibilityNotGranted)
                    return
                }
                
                // Check for cancellation
                if Task.isCancelled {
                    continuation.finish()
                    return
                }
                
                // Load maxDepth once at the start of crawl for consistent behavior and performance
                self.cachedMaxDepth = CrawlConfiguration.load().maxDepth
                
                let root = Element(element: window.element)
                
                if let menu = findMenu(root) {
                    await crawlMenuOnly(
                        menu,
                        continuation: continuation
                    )
                    continuation.finish()
                    return
                }
                
                // Get window control buttons and yield them immediately
                var itemCount = 0
                await self.crawlWindowInElementStreaming(
                    window,
                    root,
                    depth: 0,
                    itemCount: &itemCount,
                    continuation: continuation
                )
                continuation.finish()
            }
        }
    }
    
    private func findMenu(_ element: Element) -> Element? {
        guard let role = element.role else { return nil }
        
        if role == "AXMenu" {
            return element
        }
        
        for child in element.children {
            if let menu = findMenu(child) {
                return menu
            }
        }
        
        return nil
    }
    
    private func crawlMenuOnly(
        _ menu: Element,
        continuation: AsyncThrowingStream<HintTarget, Error>.Continuation
    ) async {
        for child in menu.children {
            if Task.isCancelled { return }
            
            if child.role == "AXMenuItem" && child.title?.isEmpty == false && menu.isInside(child: child) {
                let target = HintTarget(element: child)
                continuation.yield(target)
                await Task.yield()
            }
        }
    }
    
    
    /// Recursively crawls an element for actionable window items, yielding results via continuation.
    private func crawlWindowInElementStreaming(
        _ window: Window,
        _ element: Element,
        depth: Int,
        itemCount: inout Int,
        continuation: AsyncThrowingStream<HintTarget, Error>.Continuation
    ) async {
        //        print("path: \(path)")
        // Prevent infinite recursion and enforce item limit
        guard depth < cachedMaxDepth, itemCount < Self.maxItems else { return }
        
        // Check for cancellation
        if Task.isCancelled { return }
        
        for child in element.children {
            guard itemCount < Self.maxItems else { break }
            if Task.isCancelled { return }
            
            // Get role
            if child.hasActions && window.isInside(child: child) {
                let target = HintTarget(element: child)
                continuation.yield(target)
                itemCount += 1
                await Task.yield()
            }
            
            await crawlWindowInElementStreaming(
                window,
                child,
                depth: depth + 1,
                itemCount: &itemCount,
                continuation: continuation
            )
        }
    }
}
