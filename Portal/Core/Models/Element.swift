//
//  Element.swift
//  Portal
//
//  Created by matsuokashuhei on 2026/01/24.
//

import ApplicationServices
import AppKit

struct Element: Identifiable, AXUIElementable {
    let id: String
    let element: AXUIElement
    
    init(element: AXUIElement) {
        self.id = Element.generateID(element: element)
        self.element = element
    }
    
    var title: String? {
        guard let title = getAttributeValueAsString(attribute: kAXTitleAttribute as CFString) else {
            return nil
        }
        return title
    }
    
    var label: String? {
        guard let label = getAttributeValueAsString(attribute: "AXLabel" as CFString) else {
            return nil
        }
        return label
    }
    
    var enabled: Bool? {
        var ref: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &ref) == .success else {
            return nil
        }
        return ref as? Bool
    }
    
    var focused: Bool? {
        var ref: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXFocusedAttribute as CFString, &ref) == .success else {
            return nil
        }
        return ref as? Bool
    }
    
    var role: String? {
        guard let role = getAttributeValueAsString(attribute: kAXRoleAttribute as CFString) else {
            return nil
        }
        return role
    }
    
    var subrole: String? {
        guard let role = getAttributeValueAsString(attribute: kAXSubroleAttribute as CFString) else {
            return nil
        }
        return role
    }
    
    var value: String? {
        guard let value = getAttributeValueAsString(attribute: kAXValueAttribute as CFString) else {
            return nil
        }
        return value
    }
    
    var children: [Element] {
        var ref: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
            let children = ref as? [AXUIElement] else {
            return []
        }
        return children.map { child in
            Element(element: child)
        }
    }
    
    var actions: [String] {
        var ref: CFArray?
        guard
            AXUIElementCopyActionNames(element, &ref) == .success,
            let actions = ref as? [String] else {
            return []
        }
        return actions.filter {
            [
                "AXPress",
                "AXIncrement",
                "AXDecrement",
                "AXConfirm",
                "AXPick",
                "AXCancel",
                "AXRaise",
                "AXShowMenu",
                "AXDelete",
                // "AXShowAlternateUI",
                "AXShowDefaultUI",
            ].contains($0)
        }
    }
//    var action: String? {
//        guard actions.count > 0 else { return nil }
//        for action in [
//            "AXPress",
//            "AXIncrement",
//            "AXDecrement",
//            "AXConfirm",
//            "AXPick",
//            "AXCancel",
//            "AXRaise",
//            "AXShowMenu",
//            "AXDelete",
//            "AXShowAlternateUI",
//            "AXShowDefaultUI",
//        ] {
//            if actions.contains(action) {
//                return action
//            }
//        }
//        return nil
//    }
    
    func toString() -> String {
        //        [
        //            ("title", title),
        //            ("role", role),
        //            ("subrole", subrole),
        //            ("value", value)
        //        ].compactMap { key, value -> (String, String)? in
        //            guard let value else { return nil }
        //            return (key, value)
        //        }
        return "title: \(title.debugDescription), role: \(role.debugDescription), subrole: \(subrole.debugDescription), value: \(value.debugDescription), enabled: \(enabled.debugDescription), actions: \(actions.debugDescription), children: \(children.count))"
    }
    
    func focus() -> Bool {
        let result = AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        return result == .success
    }
    
    func select() -> Bool {
        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedAttribute as CFString,
            kCFBooleanTrue
        )
        return result == .success
    }
    
    var hasActions: Bool {
        guard enabled ?? true else {
            return false
        }
        guard let role = role else {
            return false
        }
        if role == "AXStaticText" && actions == ["AXShowMenu"] {
            return false
        }
        return actions
        //            .filter { $0 != "AXShowDefaultUI" }
        //            .filter {$0 != "AXShowMenu"}
        //            .filter {$0 != "AXShowAlternateUI"}
            .count > 0
    }
    
    func performAction(action: String) -> Bool {
        guard let role = role else {
            return false
        }
        switch role {
        case "AXTextField":
            return focus()
        case "AXRow":
            let _ = select()
        default:
            break
        }
        let result = AXUIElementPerformAction(element, action as CFString)
        return result == .success
    }
    
    func performAction() {
        performAction(named: nil)
    }

    func performAction(named actionName: String?) {
        guard let role = role else {
            return
        }

        let action = actionName ?? actions.first
        guard let action else {
            return
        }

        print("self: \(self.toString()), role: \(role), action: \(action)")
        switch role {
        case "AXTextField":
            let _ = focus()
        case "AXRow":
            AXUIElementPerformAction(element, action as CFString)
            let _ = select()
        default:
            AXUIElementPerformAction(element, action as CFString)
            let _ = select()
        }
    }
}
