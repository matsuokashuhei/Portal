//
//  Element.swift
//  Portal
//
//  Created by matsuokashuhei on 2026/01/24.
//

import ApplicationServices

struct Element: Identifiable {
    let id: String
    let element: AXUIElement

    init(element: AXUIElement) {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let pointerValue = UInt(bitPattern: Unmanaged.passUnretained(element).toOpaque())
        self.id = "\(pid)-0x\(String(pointerValue, radix: 16))"
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
        return actions
    }

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

    private func getAttributeValueAsString(attribute: CFString) -> String? {
        var ref: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
            let value = ref as? String else {
            return nil
        }
        return value
    }
}
