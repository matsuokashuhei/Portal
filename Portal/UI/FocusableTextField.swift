//
//  FocusableTextField.swift
//  Portal
//
//  Created by Claude Code on 2025/12/30.
//

import AppKit
import SwiftUI

/// A text field using NSViewRepresentable for AppKit integration.
/// Focus is handled by PanelController.windowDidBecomeKey via makeFirstResponder.
struct FocusableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var font: NSFont

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.font = font
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.delegate = context.coordinator
        textField.cell?.sendsActionOnEndEditing = false
        // Add accessibility identifier for XCUITest
        textField.setAccessibilityIdentifier("SearchTextField")
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusableTextField

        init(_ parent: FocusableTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }
    }
}
