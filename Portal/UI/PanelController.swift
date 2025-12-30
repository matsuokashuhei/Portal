//
//  PanelController.swift
//  Portal
//
//  Created by Claude Code on 2025/12/30.
//

import AppKit
import SwiftUI

final class PanelController {
    private var panel: NSPanel?
    private var escapeMonitor: Any?

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

        centerPanelOnScreen(panel)
        panel.makeKeyAndOrderFront(nil)
        startEscapeMonitor()
    }

    func hide() {
        stopEscapeMonitor()
        panel?.orderOut(nil)
    }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false

        let hostingView = NSHostingView(rootView: CommandPaletteView())
        panel.contentView = hostingView

        self.panel = panel
    }

    private func centerPanelOnScreen(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame

        let x = screenFrame.midX - panelFrame.width / 2
        let y = screenFrame.midY + screenFrame.height / 4 - panelFrame.height / 2

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func startEscapeMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape key
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
}

struct CommandPaletteView: View {
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            SearchFieldView(text: $searchText)
                .padding()

            Divider()

            ResultsListView()
                .frame(maxHeight: .infinity)
        }
        .frame(width: 600, height: 400)
        .background(VisualEffectBlur())
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SearchFieldView: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search commands...", text: $text)
                .textFieldStyle(.plain)
                .font(.title2)
        }
        .padding(12)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ResultsListView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Press Option+Space to activate")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
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
