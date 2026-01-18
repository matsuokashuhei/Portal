//
//  ActionExecutor.swift
//  Portal
//
//  Created by Claude Code on 2026/01/10.
//

import ApplicationServices
import Foundation

/// Protocol for executing actions on hint targets.
///
/// Implementations of this protocol are responsible for performing actions
/// on UI elements discovered by an `ElementCrawler`. Different implementations
/// can handle different types of targets (native macOS elements, web elements, etc.).
///
/// ## Thread Safety
/// All methods must be called on the main thread due to Accessibility API requirements.
@MainActor
protocol ActionExecutor {
    /// Executes an action on the specified hint target.
    ///
    /// - Parameter target: The target to execute an action on.
    /// - Returns: `.success(())` if the action was performed successfully,
    ///            `.failure(HintExecutionError)` otherwise.
    func execute(_ target: HintTarget) -> Result<Void, HintExecutionError>
}

enum TitleMatchMode {
    case exact
    case relaxed
}

struct TitleMatcher {
    static func matches(expected: String, candidates: [String], mode: TitleMatchMode) -> Bool {
        switch mode {
        case .exact:
            return candidates.contains(expected)
        case .relaxed:
            let normalizedExpected = normalizeTitle(expected)
            guard !normalizedExpected.isEmpty else {
                return false
            }
            for candidate in candidates {
                let normalizedCandidate = normalizeTitle(candidate)
                guard !normalizedCandidate.isEmpty else {
                    continue
                }
                if normalizedCandidate == normalizedExpected {
                    return true
                }
                // Allow stable prefixes to match dynamic suffixes (e.g. "Inbox" vs "Inbox (3)")
                if normalizedExpected.count >= 3,
                   isBoundaryPrefixMatch(prefix: normalizedExpected, in: normalizedCandidate) {
                    return true
                }
                if normalizedCandidate.count >= 3,
                   isBoundaryPrefixMatch(prefix: normalizedCandidate, in: normalizedExpected) {
                    return true
                }
            }
            return false
        }
    }

    private static func isBoundaryPrefixMatch(prefix: String, in value: String) -> Bool {
        guard value.hasPrefix(prefix) else {
            return false
        }
        if value.count == prefix.count {
            return true
        }
        let boundaryIndex = value.index(value.startIndex, offsetBy: prefix.count)
        return isBoundaryCharacter(value[boundaryIndex])
    }

    private static func isBoundaryCharacter(_ character: Character) -> Bool {
        for scalar in character.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                return false
            }
        }
        return true
    }

    private static func normalizeTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return collapsed.lowercased()
    }
}

struct ElementValidationSnapshot {
    let role: String?
    let subrole: String?
    let possibleTitles: [String]
}

struct ElementValidator {
    static func isValid(
        _ snapshot: ElementValidationSnapshot,
        expectedTitle: String,
        validRoles: Set<String>,
        validateTitle: Bool,
        titleMatchMode: TitleMatchMode
    ) -> Bool {
        guard let role = snapshot.role, validRoles.contains(role) else {
            return false
        }

        if let subrole = snapshot.subrole,
           AccessibilityHelper.windowControlSubroles.contains(subrole) {
            return true
        }

        guard validateTitle else {
            return true
        }

        return TitleMatcher.matches(
            expected: expectedTitle,
            candidates: snapshot.possibleTitles,
            mode: titleMatchMode
        )
    }
}

// MARK: - Shared Helper Methods

/// Extension providing shared helper methods for all ActionExecutor implementations.
/// These methods contain common logic used by both NativeAppExecutor and ElectronExecutor.
extension ActionExecutor {

    /// Validates that an AXUIElement still points to the expected item.
    ///
    /// This prevents executing the wrong item when UI has changed.
    ///
    /// - Parameters:
    ///   - element: The AXUIElement to validate.
    ///   - expectedTitle: The title that was recorded when the target was discovered.
    ///   - validRoles: Set of valid accessibility roles for this executor.
    ///   - validateTitle: Whether to validate the element's title against `expectedTitle`.
    ///                    Native apps should keep this `true` to avoid executing the wrong element.
    ///                    For highly dynamic UIs (e.g. unread counts or timestamps), keep this
    ///                    `true` and use `titleMatchMode: .relaxed` to tolerate suffix changes.
    ///                    Set this to `false` only when the UI is extremely volatile *and* the
    ///                    element identity is stable via role/hierarchy/position. Disabling title
    ///                    checks increases the risk of executing the wrong element when multiple
    ///                    elements share the same role (e.g. multiple buttons or rows).
    ///                    As an alternative, normalize titles on the caller side or use relaxed
    ///                    matching instead of disabling validation entirely.
    ///   - titleMatchMode: Controls how strictly titles are compared when `validateTitle` is `true`.
    /// - Returns: `true` if the element is still valid and matches expectations.
    func isElementValid(
        _ element: AXUIElement,
        expectedTitle: String,
        validRoles: Set<String>,
        validateTitle: Bool = true,
        titleMatchMode: TitleMatchMode = .exact
    ) -> Bool {
        #if DEBUG
        print("[ActionExecutor] isElementValid: Checking element for '\(expectedTitle)'")
        #endif

        // Verify role matches expected type first
        var roleRef: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        guard roleResult == .success, let role = roleRef as? String else {
            #if DEBUG
            print("[ActionExecutor] isElementValid: Failed to get role (result: \(roleResult.rawValue)) for '\(expectedTitle)'")
            #endif
            return false
        }

        #if DEBUG
        print("[ActionExecutor] isElementValid: Got role '\(role)' for '\(expectedTitle)'")
        #endif

        guard validRoles.contains(role) else {
            #if DEBUG
            print("[ActionExecutor] isElementValid: Role '\(role)' not in validRoles \(validRoles)")
            #endif
            return false
        }

        // Check subrole for window control buttons - they don't have title attributes
        // but can be identified by their subrole (AXCloseButton, AXMinimizeButton, etc.)
        var subrole: String? = nil
        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subroleValue = subroleRef as? String {
            subrole = subroleValue
        }

        // Verify title - check all possible title sources since crawlers use
        // title/label/description/value/help priority and we need to match any of them.
        var possibleTitles: [String] = []

        // Try direct title attribute
        var titleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
           let title = titleRef as? String, !title.isEmpty {
            possibleTitles.append(title)
        }

        // Try label attribute (used by some elements like Xcode's toggle buttons)
        var labelRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXLabel" as CFString, &labelRef) == .success,
           let label = labelRef as? String, !label.isEmpty {
            possibleTitles.append(label)
        }

        // Try description
        var descRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef) == .success,
           let desc = descRef as? String, !desc.isEmpty {
            possibleTitles.append(desc)
        }

        // Try value (used by some content labels)
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let value = valueRef as? String, !value.isEmpty {
            possibleTitles.append(value)
        }

        // Try placeholder value (used by text fields)
        var placeholderRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXPlaceholderValue" as CFString, &placeholderRef) == .success,
           let placeholder = placeholderRef as? String, !placeholder.isEmpty {
            possibleTitles.append(placeholder)
        }

        // Try help attribute (used by some buttons like Xcode's toolbar buttons)
        var helpRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXHelpAttribute as CFString, &helpRef) == .success,
           let help = helpRef as? String, !help.isEmpty {
            possibleTitles.append(help)
        }

        // Also check child elements (for sidebar items like AXRow)
        if let childTitle = getTitleFromChildren(element), !childTitle.isEmpty {
            possibleTitles.append(childTitle)
        }

        // For AXCheckBox and AXSwitch, also check sibling elements for title
        if role == "AXCheckBox" || role == "AXSwitch" {
            if let siblingTitle = getTitleFromSiblings(element), !siblingTitle.isEmpty {
                possibleTitles.append(siblingTitle)
            }
        }

        let snapshot = ElementValidationSnapshot(
            role: role,
            subrole: subrole,
            possibleTitles: possibleTitles
        )
        let isValid = ElementValidator.isValid(
            snapshot,
            expectedTitle: expectedTitle,
            validRoles: validRoles,
            validateTitle: validateTitle,
            titleMatchMode: titleMatchMode
        )

        if !isValid, validateTitle {
            let matches = TitleMatcher.matches(
                expected: expectedTitle,
                candidates: possibleTitles,
                mode: titleMatchMode
            )
            if !matches {
                #if DEBUG
                print("[ActionExecutor] isElementValid: Title '\(expectedTitle)' not found in possibleTitles: \(possibleTitles) (mode: \(titleMatchMode))")
                #endif
            }
        }

        return isValid
    }

    /// Gets title from child elements (for sidebar items like AXRow).
    ///
    /// - Parameter element: The parent AXUIElement.
    /// - Returns: The title found in child elements, or `nil` if not found.
    func getTitleFromChildren(_ element: AXUIElement) -> String? {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }

        // Look for AXStaticText elements which contain the actual label
        for child in children {
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String, role == "AXStaticText" {
                // Try value first (most common for labels)
                var valueRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &valueRef) == .success,
                   let value = valueRef as? String, !value.isEmpty {
                    return value
                }
                // Fallback to title
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let title = titleRef as? String, !title.isEmpty {
                    return title
                }
            }

            // Check grandchildren
            var grandchildrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &grandchildrenRef) == .success,
               let grandchildren = grandchildrenRef as? [AXUIElement] {
                for grandchild in grandchildren {
                    var gcRoleRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(grandchild, kAXRoleAttribute as CFString, &gcRoleRef) == .success,
                       let gcRole = gcRoleRef as? String, gcRole == "AXStaticText" {
                        var valueRef: CFTypeRef?
                        if AXUIElementCopyAttributeValue(grandchild, kAXValueAttribute as CFString, &valueRef) == .success,
                           let value = valueRef as? String, !value.isEmpty {
                            return value
                        }
                        var titleRef: CFTypeRef?
                        if AXUIElementCopyAttributeValue(grandchild, kAXTitleAttribute as CFString, &titleRef) == .success,
                           let title = titleRef as? String, !title.isEmpty {
                            return title
                        }
                    }
                }
            }
        }

        return nil
    }

    /// Gets title from sibling elements (for checkboxes/switches with separate labels).
    ///
    /// For elements inside AXCell/AXGroup containers (e.g., System Settings tables),
    /// the label may be in a sibling AXCell's child element rather than a direct sibling.
    /// In this case, we also search the grandparent's children (uncle elements).
    ///
    /// - Parameter element: The AXUIElement to check siblings of.
    /// - Returns: The title found in sibling elements, or `nil` if not found.
    func getTitleFromSiblings(_ element: AXUIElement) -> String? {
        // Get the parent element
        var parentRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentRef) == .success else {
            return nil
        }
        // Note: kAXParentAttribute always returns AXUIElement type when copy succeeds.
        // swiftlint:disable:next force_cast
        let parent = parentRef as! AXUIElement

        // Get parent's role for grandparent search decision
        let parentRole = getRole(parent)

        // Get sibling elements (children of parent)
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let siblings = childrenRef as? [AXUIElement] else {
            return nil
        }

        // Look for AXStaticText siblings that contain the label
        for sibling in siblings {
            if CFEqual(sibling, element) {
                continue
            }

            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(sibling, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String, role == "AXStaticText" {
                // Try value first (most common for labels)
                var valueRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(sibling, kAXValueAttribute as CFString, &valueRef) == .success,
                   let value = valueRef as? String, !value.isEmpty {
                    return value
                }
                // Fallback to title
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(sibling, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let title = titleRef as? String, !title.isEmpty {
                    return title
                }
            }
        }

        // If parent is AXCell or AXGroup, look in grandparent's children (uncle elements).
        // This handles cases like System Settings tables where:
        // AXRow > AXCell (label) > AXStaticText "App Store"
        // AXRow > AXCell (toggle) > AXSwitch  <- we're here
        if parentRole == "AXCell" || parentRole == "AXGroup" {
            if let uncleTitle = AccessibilityHelper.getTitleFromUncles(parent: parent, skipElement: parent) {
                return uncleTitle
            }
        }

        // Fallback: try the parent's description
        var descRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(parent, kAXDescriptionAttribute as CFString, &descRef) == .success,
           let desc = descRef as? String, !desc.isEmpty {
            return desc
        }

        return nil
    }

    /// Gets the boolean value of a checkbox or switch element.
    ///
    /// - Parameter element: The AXUIElement to get the value from.
    /// - Returns: The boolean value, or `nil` if the value cannot be read.
    func getCheckboxValue(_ element: AXUIElement) -> Bool? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success else {
            return nil
        }

        if let intValue = valueRef as? Int {
            return intValue != 0
        }
        if let boolValue = valueRef as? Bool {
            return boolValue
        }
        if let numberValue = valueRef as? NSNumber {
            return numberValue.boolValue
        }
        return nil
    }

    /// Checks if an element is an AXButton.
    ///
    /// - Parameter element: The AXUIElement to check.
    /// - Returns: `true` if the element is an AXButton.
    func isButtonElement(_ element: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else {
            return false
        }
        return role == "AXButton"
    }

    /// Tries to press child buttons recursively.
    ///
    /// This is used as a fallback when the main element's AXPress action
    /// succeeds but doesn't actually do anything (common with container elements).
    ///
    /// - Parameters:
    ///   - element: The parent element to search for child buttons.
    ///   - depth: Current search depth (default 0).
    ///   - maxDepth: Maximum depth to prevent stack overflow (default 5).
    /// - Returns: `true` if a child button was successfully pressed.
    func tryPressChildButtons(_ element: AXUIElement, depth: Int = 0, maxDepth: Int = 5) -> Bool {
        guard depth < maxDepth else {
            return false
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return false
        }

        for child in children {
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String, role == "AXButton" {
                let result = AXUIElementPerformAction(child, kAXPressAction as CFString)
                if result == .success {
                    return true
                }
            }

            if tryPressChildButtons(child, depth: depth + 1, maxDepth: maxDepth) {
                return true
            }
        }

        return false
    }

    /// Gets the role of an AXUIElement.
    ///
    /// - Parameter element: The AXUIElement to get the role from.
    /// - Returns: The role string, or `nil` if the role cannot be read.
    func getRole(_ element: AXUIElement) -> String? {
        var roleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        guard result == .success, let role = roleRef as? String else {
            return nil
        }
        return role
    }
}
