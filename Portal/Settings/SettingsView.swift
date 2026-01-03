//
//  SettingsView.swift
//  Portal
//
//  Created by Claude Code on 2026/01/01.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
        }
        .frame(width: 450, height: 250)
    }
}

struct GeneralSettingsView: View {
    @AppStorage(SettingsKey.hotkeyModifier) private var modifierRaw = ModifierKey.option.rawValue
    @AppStorage(SettingsKey.hotkeyKey) private var keyRaw = HotkeyKey.space.rawValue

    @State private var isAccessibilityGranted = AccessibilityService.isGranted

    private var selectedModifier: Binding<ModifierKey> {
        Binding(
            get: { ModifierKey(rawValue: modifierRaw) ?? .option },
            set: {
                modifierRaw = $0.rawValue
                notifyHotkeyChanged()
            }
        )
    }

    private var selectedKey: Binding<HotkeyKey> {
        Binding(
            get: { HotkeyKey(rawValue: keyRaw) ?? .space },
            set: {
                keyRaw = $0.rawValue
                notifyHotkeyChanged()
            }
        )
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Hint Mode Hotkey")
                    Spacer()

                    Picker("Modifier", selection: selectedModifier) {
                        ForEach(ModifierKey.allCases) { modifier in
                            Text("\(modifier.symbol) \(modifier.rawValue)")
                                .tag(modifier)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)

                    Text("+")
                        .foregroundStyle(.secondary)

                    Picker("Key", selection: selectedKey) {
                        ForEach(HotkeyKey.allCases) { key in
                            Text(key.rawValue)
                                .tag(key)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }

                Text("Current: \(selectedModifier.wrappedValue.symbol) \(selectedKey.wrappedValue.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Hint Mode")
            }

            Section {
                HStack {
                    Text("Accessibility Permission")
                    Spacer()

                    if isAccessibilityGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Granted", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                if !isAccessibilityGranted {
                    Text("Portal needs accessibility permission to navigate window elements in other applications.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Grant Permission...") {
                        AccessibilityService.openAccessibilitySettings()
                    }
                }
            } header: {
                Text("Permissions")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshAccessibilityStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityStatus()
        }
    }

    private func notifyHotkeyChanged() {
        NotificationCenter.default.post(name: .hotkeyConfigurationChanged, object: nil)
    }

    private func refreshAccessibilityStatus() {
        isAccessibilityGranted = AccessibilityService.isGranted
    }
}
