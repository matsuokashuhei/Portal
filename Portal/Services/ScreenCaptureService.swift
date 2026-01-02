//
//  ScreenCaptureService.swift
//  Portal
//
//  Created by Claude Code on 2026/01/02.
//

import ScreenCaptureKit
import AppKit
import ApplicationServices

/// Error types for screen capture operations.
enum ScreenCaptureError: Error, LocalizedError {
    case screenRecordingNotGranted
    case noWindowFound
    case captureFailure(String)
    case invalidRect

    var errorDescription: String? {
        switch self {
        case .screenRecordingNotGranted:
            return "Portal needs Screen Recording permission to show item icons. Please enable access in System Settings > Privacy & Security > Screen Recording."
        case .noWindowFound:
            return "No window found for capture."
        case .captureFailure(let detail):
            return "Screen capture failed: \(detail)"
        case .invalidRect:
            return "Invalid capture region."
        }
    }
}

/// Service for capturing screen content using ScreenCaptureKit.
///
/// This service captures window screenshots and extracts icon-sized regions
/// for display in the command palette.
///
/// ## Performance
/// - Caches window screenshots for 1 second to avoid repeated captures
/// - Extracts multiple regions from a single capture for efficiency
///
/// ## Requirements
/// - macOS 12.3+ for ScreenCaptureKit
/// - Screen Recording permission (optional, falls back to SF Symbols)
@MainActor
final class ScreenCaptureService {
    /// Standard icon size for content items.
    static let iconSize = CGSize(width: 32, height: 32)

    /// Cache expiry time in seconds.
    private static let cacheExpiry: TimeInterval = 1.0

    /// Cached window screenshot for efficient region extraction.
    private var windowCache: (windowID: CGWindowID, image: CGImage, frame: CGRect, timestamp: Date)?

    // MARK: - Permission Management

    /// Checks if Screen Recording permission is granted.
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Requests Screen Recording permission asynchronously.
    ///
    /// This method initiates the permission request but returns immediately.
    /// The actual permission dialog is shown asynchronously, so the caller should not
    /// expect `isGranted` to return true immediately after calling this method.
    ///
    /// To ensure the dialog appears on modern macOS, this method also attempts to access
    /// shareable content via ScreenCaptureKit in a background task.
    ///
    /// - Note: This is designed to be called once at app launch. The permission state
    ///   should be checked via `isGranted` when actually capturing content.
    static func requestPermission() {
        // Try the standard API first
        _ = CGRequestScreenCaptureAccess()

        // On modern macOS, also try ScreenCaptureKit to ensure dialog appears
        Task { @MainActor in
            _ = try? await SCShareableContent.current
        }
    }

    /// Opens System Settings directly to the Screen Recording privacy pane.
    static func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systemsettings:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Window Capture

    /// Captures icons for multiple elements from the same window.
    ///
    /// This method captures the window once and extracts multiple regions efficiently.
    ///
    /// - Parameters:
    ///   - elements: Array of tuples containing (AXUIElement, CGRect frame)
    ///   - windowID: The CGWindowID of the target window
    ///   - windowFrame: The frame of the target window in screen coordinates
    /// - Returns: Dictionary mapping element indices to their captured icons
    func captureIcons(
        for elements: [(element: AXUIElement, frame: CGRect)],
        windowID: CGWindowID,
        windowFrame: CGRect
    ) async throws -> [Int: NSImage] {
        guard Self.isGranted else {
            throw ScreenCaptureError.screenRecordingNotGranted
        }

        // Check cache or capture new window image
        let windowImage = try await getWindowImage(windowID: windowID, windowFrame: windowFrame)

        var results: [Int: NSImage] = [:]

        for (index, elementInfo) in elements.enumerated() {
            if let icon = extractRegion(elementInfo.frame, from: windowImage, windowFrame: windowFrame) {
                results[index] = icon
            }
        }

        return results
    }

    /// Gets cached or captures new window image.
    private func getWindowImage(windowID: CGWindowID, windowFrame: CGRect) async throws -> CGImage {
        // Check cache (including frame to handle window resize)
        if let cached = windowCache,
           cached.windowID == windowID,
           cached.frame == windowFrame,
           Date().timeIntervalSince(cached.timestamp) < Self.cacheExpiry {
            return cached.image
        }

        // Find the window in shareable content
        let content = try await SCShareableContent.current
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw ScreenCaptureError.noWindowFound
        }

        // Configure capture
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()

        // Use the main screen's backing scale factor for correct resolution
        let scale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2.0
        config.width = Int(windowFrame.width * scale)
        config.height = Int(windowFrame.height * scale)
        config.scalesToFit = false
        config.showsCursor = false

        // Capture the window
        do {
            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )

            // Cache the result
            windowCache = (windowID, cgImage, windowFrame, Date())

            return cgImage
        } catch {
            // Invalidate cache on capture failure to avoid using stale images
            windowCache = nil
            throw error
        }
    }

    /// Extracts an icon-sized region from a window image.
    ///
    /// - Parameters:
    ///   - elementFrame: The frame of the element in screen coordinates
    ///   - windowImage: The captured window image
    ///   - windowFrame: The frame of the window in screen coordinates
    /// - Returns: The extracted and resized icon, or nil if extraction fails
    private func extractRegion(_ elementFrame: CGRect, from windowImage: CGImage, windowFrame: CGRect) -> NSImage? {
        // Convert from element (Accessibility) coordinates to window-local coordinates
        // Note: Accessibility API returns coordinates with origin at top-left
        //       (unlike general screen coordinates which use bottom-left), and
        //       CGImage also uses a top-left origin, so no Y-axis flip is needed.
        let localRect = CGRect(
            x: elementFrame.origin.x - windowFrame.origin.x,
            y: elementFrame.origin.y - windowFrame.origin.y,
            width: elementFrame.width,
            height: elementFrame.height
        )

        // Validate the rect is within the window
        guard localRect.origin.x >= 0,
              localRect.origin.y >= 0,
              localRect.maxX <= windowFrame.width,
              localRect.maxY <= windowFrame.height else {
            return nil
        }

        // Scale for Retina (image is captured at 2x)
        let scale: CGFloat = CGFloat(windowImage.width) / windowFrame.width
        let scaledRect = CGRect(
            x: localRect.origin.x * scale,
            y: localRect.origin.y * scale,
            width: localRect.width * scale,
            height: localRect.height * scale
        )

        // Ensure we have valid dimensions
        guard scaledRect.width > 0, scaledRect.height > 0 else {
            return nil
        }

        // Crop the image
        guard let croppedImage = windowImage.cropping(to: scaledRect) else {
            return nil
        }

        // Create NSImage and resize to icon size
        let nsImage = NSImage(cgImage: croppedImage, size: localRect.size)
        return resizeImage(nsImage, to: Self.iconSize)
    }

    /// Resizes an image to the specified size.
    private func resizeImage(_ image: NSImage, to size: CGSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(
                in: rect,
                from: CGRect(origin: .zero, size: image.size),
                operation: .copy,
                fraction: 1.0
            )
            return true
        }
    }

    /// Clears the window cache.
    func clearCache() {
        windowCache = nil
    }
}
