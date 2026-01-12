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
            ExclusionsSettingsView()
                .tabItem {
                    Label("Exclusions", systemImage: "nosign")
                }
        }
        .frame(width: 450, height: 350)
    }
}

struct GeneralSettingsView: View {
    @AppStorage(SettingsKey.hotkeyModifier) private var modifierRaw = ModifierKey.none.rawValue
    @AppStorage(SettingsKey.hotkeyKey) private var keyRaw = HotkeyKey.f.rawValue

    @State private var isAccessibilityGranted = AccessibilityService.isGranted

    private var selectedModifier: Binding<ModifierKey> {
        Binding(
            get: { ModifierKey(rawValue: modifierRaw) ?? .none },
            set: {
                modifierRaw = $0.rawValue
                notifyHotkeyChanged()
            }
        )
    }

    private var selectedKey: Binding<HotkeyKey> {
        Binding(
            get: { HotkeyKey(rawValue: keyRaw) ?? .f },
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

                    if selectedModifier.wrappedValue != .none {
                        Text("+")
                            .foregroundStyle(.secondary)
                    }

                    Picker("Key", selection: selectedKey) {
                        ForEach(HotkeyKey.allCases) { key in
                            Text(key.rawValue)
                                .tag(key)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }

                Text(
                    selectedModifier.wrappedValue == .none
                    ? "Current: \(selectedKey.wrappedValue.rawValue)"
                    : "Current: \(selectedModifier.wrappedValue.symbol) \(selectedKey.wrappedValue.rawValue)"
                )
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

// MARK: - ExclusionsSettingsView

struct ExclusionsSettingsView: View {
    @State private var excludedApps: [ExcludedApp] = []
    @State private var showingAppPicker = false

    var body: some View {
        Form {
            Section {
                if excludedApps.isEmpty {
                    Text("No apps excluded")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(excludedApps) { app in
                        HStack {
                            AppIconView(bundleIdentifier: app.bundleIdentifier)
                                .frame(width: 20, height: 20)
                            Text(app.displayName)
                            Spacer()
                            Button {
                                deleteApp(app)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } header: {
                Text("Excluded Applications")
            } footer: {
                Text("Portal hotkey will not activate when these applications are frontmost.")
            }

            Section {
                Button("Add Application...") {
                    showingAppPicker = true
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAppPicker) {
            AppPickerView(excludedBundleIds: Set(excludedApps.map(\.bundleIdentifier))) { app in
                addApp(app)
            }
        }
        .onAppear {
            loadConfiguration()
        }
    }

    private func loadConfiguration() {
        let config = ExcludedAppsConfiguration.load()
        excludedApps = config.excludedApps
    }

    private func saveConfiguration() {
        let config = ExcludedAppsConfiguration(excludedApps: excludedApps)
        config.save()
        NotificationCenter.default.post(name: .excludedAppsConfigurationChanged, object: nil)
    }

    private func addApp(_ app: ExcludedApp) {
        guard !excludedApps.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) else {
            return
        }
        excludedApps.append(app)
        saveConfiguration()
    }

    private func deleteApp(_ app: ExcludedApp) {
        excludedApps.removeAll { $0.bundleIdentifier == app.bundleIdentifier }
        saveConfiguration()
    }
}

// MARK: - AppIconView

struct AppIconView: View {
    let bundleIdentifier: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - AppPickerView

struct AppPickerView: View {
    let excludedBundleIds: Set<String>
    let onSelect: (ExcludedApp) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var applications: [AppInfo] = []
    @State private var searchText = ""

    private var filteredApplications: [AppInfo] {
        let available = applications.filter { !excludedBundleIds.contains($0.bundleIdentifier) }
        if searchText.isEmpty {
            return available
        }
        return available.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select Application")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 8)

            List(filteredApplications) { app in
                Button {
                    onSelect(ExcludedApp(
                        bundleIdentifier: app.bundleIdentifier,
                        displayName: app.displayName
                    ))
                    dismiss()
                } label: {
                    HStack {
                        Image(nsImage: app.icon)
                            .resizable()
                            .frame(width: 24, height: 24)
                        Text(app.displayName)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 400, height: 500)
        .onAppear {
            loadApplications()
        }
    }

    private func loadApplications() {
        DispatchQueue.global(qos: .userInitiated).async {
            var appData: [(bundleId: String, displayName: String, path: String)] = []

            // Scan /Applications and ~/Applications directories
            let applicationDirs = [
                URL(fileURLWithPath: "/Applications"),
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
            ]

            for dir in applicationDirs {
                guard let contents = try? FileManager.default.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.isApplicationKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                for url in contents where url.pathExtension == "app" {
                    if let bundle = Bundle(url: url),
                       let bundleId = bundle.bundleIdentifier {
                        let displayName = (bundle.infoDictionary?["CFBundleName"] as? String)
                            ?? (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                            ?? url.deletingPathExtension().lastPathComponent
                        appData.append((bundleId, displayName, url.path))
                    }
                }
            }

            // Sort by display name
            let sortedData = appData.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }

            // Get icons on main thread (NSWorkspace methods should be called from main thread)
            DispatchQueue.main.async {
                self.applications = sortedData.map { data in
                    AppInfo(
                        bundleIdentifier: data.bundleId,
                        displayName: data.displayName,
                        icon: NSWorkspace.shared.icon(forFile: data.path)
                    )
                }
            }
        }
    }
}

/// Information about an installed application.
struct AppInfo: Identifiable {
    let bundleIdentifier: String
    let displayName: String
    let icon: NSImage

    var id: String { bundleIdentifier }
}
