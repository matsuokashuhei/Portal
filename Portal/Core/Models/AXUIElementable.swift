//
//  AXUIElementable.swift
//  Portal
//
//  Created by matsuokashuhei on 2026/01/31.
//
import AppKit

protocol AXUIElementable {
    var element: AXUIElement { get }
//    var frame: CGRect? { get }
}

extension AXUIElementable {
    static func generateID(element: AXUIElement) -> String {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let pointerValue = UInt(bitPattern: Unmanaged.passUnretained(element).toOpaque())
        return  "\(pid)-0x\(String(pointerValue, radix: 16))"
    }
    
    func getAttributeValueAsString(attribute: CFString) -> String? {
        var ref: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
            let value = ref as? String else {
            return nil
        }
        return value
    }
    
    func getAttributeValueAsUIElement(attribute: CFString) -> AXUIElement? {
        var ref: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
            let button = ref
        else {
            return nil
        }
        return button as! AXUIElement
    }
    
    func getAttributeValueAsRef(attribute: CFString) -> CFTypeRef? {
        var ref: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute, &ref) == .success else {
            return nil
        }
        return ref
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
        return Self.convertToScreenCoordinates(rect)
    }
    
    func isInside(child: Element) -> Bool {
        guard
            let frame = self.frame,
            let childFrame = child.frame else {
            return false
        }
        return frame.contains(childFrame.origin)
    }
    
    static func convertToScreenCoordinates(_ axRect: CGRect) -> CGRect {
        guard let primaryScreen = NSScreen.screens.first else {
            return axRect
        }

        let screenHeight = primaryScreen.frame.height

        // Flip Y coordinate: bottom = screenHeight - top - height
        let convertedY = screenHeight - axRect.origin.y - axRect.size.height

        return CGRect(
            x: axRect.origin.x,
            y: convertedY,
            width: axRect.size.width,
            height: axRect.size.height
        )
    }
    
    // No used
    static func getFocusedUIElement() -> Element? {
        var ref: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                AXUIElementCreateSystemWide(),
                kAXFocusedUIElementAttribute as CFString,
                &ref
            ) == .success else {
            return nil
        }
        return Element(element: ref as! AXUIElement)
    }
}
