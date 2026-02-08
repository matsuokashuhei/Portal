//
//  Window.swift
//  Portal
//
//  Created by matsuokashuhei on 2026/01/24.
//
import AppKit

struct Window: AXUIElementable {
    let element: AXUIElement
    init?(_ runningApplication: NSRunningApplication) {
        let app = AXUIElementCreateApplication(runningApplication.processIdentifier)
        var ref: CFTypeRef?
        
        guard
            AXUIElementCopyAttributeValue(
                app,
                kAXFocusedWindowAttribute as CFString,
                &ref
            ) == .success else {
            return nil
        }
        // swiftlint:disable:next force_cast
        let window = ref as! AXUIElement
        self.element = window
    }
}
