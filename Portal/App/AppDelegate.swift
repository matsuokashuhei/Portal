//
//  AppDelegate.swift
//  Portal
//
//  Created by Claude Code on 2025/12/30.
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotkeyManager: HotkeyManager?
    private let panelController = PanelController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupHotkeyManager()
    }

    private func setupHotkeyManager() {
        hotkeyManager = HotkeyManager { [weak self] in
            self?.panelController.toggle()
        }
        hotkeyManager?.start()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "command", accessibilityDescription: "Portal Menu")
        }

        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit Portal", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector("showSettingsWindow:"), to: nil, from: nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
