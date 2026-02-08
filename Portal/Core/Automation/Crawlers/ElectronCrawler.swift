//
//  ElectronCrawler.swift
//  Portal
//
//  Created by Claude Code on 2026/01/10.
//

import ApplicationServices
import AppKit

/// Crawler specialized for Electron applications.
///
/// Electron apps use Chromium for rendering web content, which requires special handling:
/// 1. Enable AXManualAccessibility to expose web elements
/// 2. Crawl AXWebArea elements for web content
/// 3. Also crawl native chrome (toolbars, sidebars) using standard accessibility
///
/// ## Supported Electron Apps
/// - Slack, VS Code, Discord, Notion, Figma, 1Password, Obsidian, etc.
///
/// ## Web Element Roles
/// - AXLink - Links
/// - AXButton - Buttons
/// - AXTextField / AXTextArea - Input fields
/// - AXCheckBox / AXRadioButton - Form elements
/// - AXMenuItem - Menu items
/// - AXWebArea - Web content containers
@MainActor
final class ElectronCrawler: ElementCrawler {
    // MARK: - ElementCrawler Protocol

    /// Electron apps use screen-local coordinates (no Y-flip needed).
    let coordinateSystem: HintCoordinateSystem = .electron

    // MARK: - Constants

    /// Cached maximum depth for the current crawl operation.
    /// Updated at the start of each crawl to pick up setting changes.
    private var cachedMaxDepth: Int = CrawlConfiguration.defaultMaxDepth

    /// Maximum number of items to return.
    private static let maxItems = 500

    /// The detector used to identify Electron apps.
    private let detector: ElectronAppDetector

    /// Native app crawler for handling native chrome elements.
    private let nativeCrawler: NativeAppCrawler

    /// Frame similarity threshold to treat two frames as the same UI element.
    private static let frameSimilarityThreshold: CGFloat = 0.5

    /// Creates an ElectronCrawler with the default detector.
    init() {
        self.detector = ElectronAppDetector()
        self.nativeCrawler = NativeAppCrawler()
    }

    /// Creates an ElectronCrawler with a custom detector (for testing).
    init(detector: ElectronAppDetector, nativeCrawler: NativeAppCrawler) {
        self.detector = detector
        self.nativeCrawler = nativeCrawler
    }

    // MARK: - ElementCrawler Protocol

    /// Crawls UI elements from the specified application as an async stream.
    ///
    /// This method yields elements as they are discovered, enabling progressive
    /// rendering of hint labels. Use this for better responsiveness when crawling
    /// applications with many UI elements.
    ///
    /// - Parameter window: The window to crawl elements from.
    /// - Returns: An async stream of discovered hint targets.
    func crawlElementsStream(_ window: Window) -> AsyncThrowingStream<HintTarget, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                guard AccessibilityService.isGranted else {
                    continuation.finish(throwing: NativeAppCrawlerError.accessibilityNotGranted)
                    return
                }

                // Load maxDepth once at the start of crawl for consistent behavior and performance
                self.cachedMaxDepth = CrawlConfiguration.load().maxDepth

                continuation.finish()
            }
        }
    }

    // MARK: - Frame Utilities

    /// Determines whether two frames represent the same UI element based on overlap and size similarity.
    nonisolated static func framesOverlapSignificantly(_ itemFrame: CGRect, _ existingFrame: CGRect) -> Bool {
        let intersection = itemFrame.intersection(existingFrame)
        guard !intersection.isNull else { return false }

        let itemArea = itemFrame.width * itemFrame.height
        let existingArea = existingFrame.width * existingFrame.height
        guard itemArea > 0, existingArea > 0 else { return false }

        let smallerArea = min(itemArea, existingArea)
        let overlapArea = intersection.width * intersection.height
        let overlapRatio = overlapArea / smallerArea

        let widthRatio = min(itemFrame.width, existingFrame.width) / max(itemFrame.width, existingFrame.width)
        let heightRatio = min(itemFrame.height, existingFrame.height) / max(itemFrame.height, existingFrame.height)
        if widthRatio < Self.frameSimilarityThreshold || heightRatio < Self.frameSimilarityThreshold {
            return false
        }

        return overlapRatio > 0.5
    }

    enum FrameSource: String {
        case axFrame = "AXFrame"
        case positionSize = "AXPosition+AXSize"
        case none
    }

    nonisolated static func resolveFrame(axFrame: CGRect?, position: CGPoint?, size: CGSize?) -> (CGRect?, FrameSource) {
        if let axFrame {
            return (axFrame, .axFrame)
        }
        if let position, let size {
            return (CGRect(origin: position, size: size), .positionSize)
        }
        return (nil, .none)
    }

    nonisolated static func estimatedFallbackFrame(parentFrame: CGRect, childIndex: Int?) -> CGRect {
        let shortestSide = max(1.0, min(parentFrame.width, parentFrame.height))
        let baseSize = shortestSide * 0.3
        let cappedBase = min(baseSize, 44.0)
        let estimatedSize = min(shortestSide, max(12.0, cappedBase))

        var originX = parentFrame.minX
        var originY = parentFrame.minY

        if let childIndex {
            let offsetStep = max(6.0, estimatedSize * 0.6)
            let maxHintsPerRow = max(1, Int(parentFrame.width / offsetStep))
            let column = childIndex % maxHintsPerRow
            let row = childIndex / maxHintsPerRow
            originX = parentFrame.minX + CGFloat(column) * offsetStep
            originY = parentFrame.minY + CGFloat(row) * offsetStep
        }

        return CGRect(
            x: originX,
            y: originY,
            width: estimatedSize,
            height: estimatedSize
        )
    }
}
