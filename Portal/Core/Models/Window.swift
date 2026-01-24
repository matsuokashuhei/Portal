//
//  Window.swift
//  Portal
//
//  Created by matsuokashuhei on 2026/01/24.
//
import AppKit

struct Window {
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
    
    var closeButton: Element? {
        guard let button = getAttributeValueAsUIElement(attribute: kAXCloseButtonAttribute as CFString) else { return nil }
        return Element(element: button)
    }
    
    var minimizeButton: Element? {
        guard let button = getAttributeValueAsUIElement(attribute: kAXMinimizeButtonAttribute as CFString) else { return nil }
        return Element(element: button)
    }
    
    var zoomButton: Element? {
        guard let button = getAttributeValueAsUIElement(attribute: kAXZoomButtonAttribute as CFString) else { return nil }
        return Element(element: button)
    }
    
    var fullScreenButton: Element? {
        guard let button = getAttributeValueAsUIElement(attribute: kAXFullScreenButtonAttribute as CFString) else { return nil }
        return Element(element: button)
    }
    
    var frame: CGRect? {
        var position = CGPoint.zero
        guard
            let ref = getAttributeValueAsRef(attribute: kAXPositionAttribute as CFString),
            CFGetTypeID(ref) == AXValueGetTypeID(),
            AXValueGetValue(ref as! AXValue, .cgPoint, &position) else {
            return nil
        }
        var size = CGSize.zero
        guard
            let ref = getAttributeValueAsRef(attribute: kAXSizeAttribute as CFString),
            CFGetTypeID(ref) == AXValueGetTypeID(),
            AXValueGetValue(ref as! AXValue, .cgSize, &size) else {
            return nil
        }
        let rect = CGRect(origin: position, size: size)
        return AccessibilityHelper.convertToScreenCoordinates(rect)
    }

    private func getAttributeValueAsUIElement(attribute: CFString) -> AXUIElement? {
        var ref: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
            let button = ref
        else {
            return nil
        }
        return button as! AXUIElement
    }

    private func getAttributeValueAsRef(attribute: CFString) -> CFTypeRef? {
        var ref: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute, &ref) == .success else {
            return nil
        }
        return ref
    }
}
