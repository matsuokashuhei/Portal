//
//  Constants.swift
//  Portal
//
//  Created by Claude Code on 2026/01/01.
//

/// Application-wide constants.
enum Constants {
    /// Bundle identifiers for known applications.
    enum BundleIdentifier {
        /// Finder's bundle identifier.
        /// Finder requires special handling because its menus change dynamically
        /// based on selection state, and the app itself cannot be activated
        /// through normal NSRunningApplication methods.
        static let finder = "com.apple.finder"
    }
}
