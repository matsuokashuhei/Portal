//
//  HotkeyManager.swift
//  Portal
//
//  Created by Claude Code on 2025/12/30.
//

import AppKit

final class HotkeyManager {
    private static let spaceKeyCode: UInt16 = 49

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let onHotkeyPressed: () -> Void

    init(onHotkeyPressed: @escaping () -> Void) {
        self.onHotkeyPressed = onHotkeyPressed
    }

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .option && event.keyCode == Self.spaceKeyCode {
            DispatchQueue.main.async { [weak self] in
                self?.onHotkeyPressed()
            }
        }
    }

    deinit {
        stop()
    }
}
