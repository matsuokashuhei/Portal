//
//  PanelController.swift
//  Portal
//
//  Created by Claude Code on 2025/12/30.
//

import AppKit
import SwiftUI

final class PanelController: NSObject, NSWindowDelegate {
    private static let escapeKeyCode: UInt16 = 53
    static let panelSize = NSSize(width: 600, height: 400)

    private var panel: NSPanel?
    private var escapeMonitor: Any?
    private var hasBeenPositioned = false

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        if panel == nil {
            createPanel()
        }

        guard let panel = panel else { return }

        if !hasBeenPositioned {
            centerPanelOnScreen(panel)
            hasBeenPositioned = true
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        stopEscapeMonitor()
        startEscapeMonitor()
    }

    func hide() {
        stopEscapeMonitor()
        panel?.orderOut(nil)
        panel = nil
        hasBeenPositioned = false
    }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.title = "Portal Command Palette"
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.delegate = self

        let hostingView = NSHostingView(rootView: CommandPaletteView())
        panel.contentView = hostingView

        self.panel = panel
    }

    private func centerPanelOnScreen(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame

        let x = screenFrame.midX - panelFrame.width / 2
        let y = screenFrame.maxY - screenFrame.height / 4 - panelFrame.height / 2

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func startEscapeMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == Self.escapeKeyCode && modifiers.isEmpty {
                self?.hide()
                return nil
            }
            return event
        }
    }

    private func stopEscapeMonitor() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    deinit {
        stopEscapeMonitor()
    }
}

struct CommandPaletteView: View {
    @State private var searchText = ""
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            SearchFieldView(text: $searchText, isFocused: $isSearchFieldFocused)
                .padding()

            Divider()

            ResultsListView()
                .frame(maxHeight: .infinity)
        }
        .frame(width: PanelController.panelSize.width, height: PanelController.panelSize.height)
        .background(VisualEffectBlur())
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("CommandPaletteView")
        .onAppear {
            isSearchFieldFocused = true
        }
    }
}

struct SearchFieldView: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            TextField("Search commands...", text: $text)
                .textFieldStyle(.plain)
                .font(.title2)
                .focused(isFocused)
                .accessibilityLabel("Search commands")
                .accessibilityIdentifier("SearchTextField")
        }
        .padding(12)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("SearchFieldView")
    }
}

struct ResultsListView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Type to search commands...")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
        .accessibilityIdentifier("ResultsListView")
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
