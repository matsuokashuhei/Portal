//
//  ExcludedAppsConfiguration.swift
//  Portal
//
//  Created by Claude Code on 2026/01/12.
//

import Foundation

/// Represents an application excluded from Portal's hotkey activation.
struct ExcludedApp: Codable, Equatable, Identifiable {
    /// The bundle identifier of the excluded application (e.g., "com.microsoft.VSCode").
    let bundleIdentifier: String
    /// The display name of the application (e.g., "Visual Studio Code").
    let displayName: String

    var id: String { bundleIdentifier }
}

/// Configuration for applications excluded from Portal's hotkey activation.
///
/// When an excluded application is frontmost, Portal will not respond to the configured hotkey.
/// This is useful for applications like VS Code or Terminal where the hotkey might conflict
/// with the application's own shortcuts.
struct ExcludedAppsConfiguration: Equatable {
    /// List of excluded applications.
    var excludedApps: [ExcludedApp]

    /// Default configuration with no excluded apps.
    static let `default` = ExcludedAppsConfiguration(excludedApps: [])

    /// Loads configuration from UserDefaults, falling back to defaults.
    /// - Parameter defaults: UserDefaults instance to read from. Defaults to `.standard`.
    static func load(from defaults: UserDefaults = .standard) -> ExcludedAppsConfiguration {
        guard let data = defaults.data(forKey: SettingsKey.excludedApps) else {
            return .default
        }

        do {
            let excludedApps = try JSONDecoder().decode([ExcludedApp].self, from: data)
            return ExcludedAppsConfiguration(excludedApps: excludedApps)
        } catch {
            #if DEBUG
            print("[ExcludedAppsConfiguration] Failed to decode: \(error)")
            #endif
            return .default
        }
    }

    /// Saves configuration to UserDefaults.
    /// - Parameter defaults: UserDefaults instance to write to. Defaults to `.standard`.
    func save(to defaults: UserDefaults = .standard) {
        do {
            let data = try JSONEncoder().encode(excludedApps)
            defaults.set(data, forKey: SettingsKey.excludedApps)
        } catch {
            #if DEBUG
            print("[ExcludedAppsConfiguration] Failed to encode: \(error)")
            #endif
        }
    }

    /// Checks if an application with the given bundle identifier is excluded.
    /// - Parameter bundleIdentifier: The bundle identifier to check.
    /// - Returns: `true` if the application is in the exclusion list.
    func isExcluded(bundleIdentifier: String) -> Bool {
        excludedApps.contains { $0.bundleIdentifier == bundleIdentifier }
    }
}
