//
//  HotkeyConfiguration.swift
//  Portal
//
//  Created by Claude Code on 2026/01/01.
//

import AppKit

/// Supported modifier keys for hotkey configuration.
enum ModifierKey: String, CaseIterable, Identifiable {
    case option = "Option"
    case command = "Command"
    case control = "Control"
    case shift = "Shift"
    case none = "None"

    var id: String { rawValue }

    /// Symbol for display (e.g., in UI)
    var symbol: String {
        switch self {
        case .option: return "⌥"
        case .command: return "⌘"
        case .control: return "⌃"
        case .shift: return "⇧"
        case .none: return ""
        }
    }

    /// NSEvent.ModifierFlags equivalent
    var eventModifier: NSEvent.ModifierFlags {
        switch self {
        case .option: return .option
        case .command: return .command
        case .control: return .control
        case .shift: return .shift
        case .none: return []
        }
    }

    /// CGEventFlags equivalent for CGEventTap
    var cgEventMask: CGEventFlags {
        switch self {
        case .option: return .maskAlternate
        case .command: return .maskCommand
        case .control: return .maskControl
        case .shift: return .maskShift
        case .none: return []
        }
    }

    /// Whether this modifier requires no modifier key to be pressed.
    var isNone: Bool {
        self == .none
    }
}

/// Supported keys for hotkey configuration.
enum HotkeyKey: String, CaseIterable, Identifiable {
    case space = "Space"
    case tab = "Tab"
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"
    case e = "E"
    case f = "F"
    case g = "G"
    case h = "H"
    case i = "I"
    case j = "J"
    case k = "K"
    case l = "L"
    case m = "M"
    case n = "N"
    case o = "O"
    case p = "P"
    case q = "Q"
    case r = "R"
    case s = "S"
    case t = "T"
    case u = "U"
    case v = "V"
    case w = "W"
    case x = "X"
    case y = "Y"
    case z = "Z"

    var id: String { rawValue }

    /// Carbon key code for CGEventTap and NSEvent
    var keyCode: Int64 {
        switch self {
        case .space: return 49
        case .tab: return 48
        case .a: return 0
        case .b: return 11
        case .c: return 8
        case .d: return 2
        case .e: return 14
        case .f: return 3
        case .g: return 5
        case .h: return 4
        case .i: return 34
        case .j: return 38
        case .k: return 40
        case .l: return 37
        case .m: return 46
        case .n: return 45
        case .o: return 31
        case .p: return 35
        case .q: return 12
        case .r: return 15
        case .s: return 1
        case .t: return 17
        case .u: return 32
        case .v: return 9
        case .w: return 13
        case .x: return 7
        case .y: return 16
        case .z: return 6
        }
    }
}

/// Represents a configurable hotkey combination.
struct HotkeyConfiguration: Equatable {
    let modifier: ModifierKey
    let key: HotkeyKey

    /// Default hotkey: F key (no modifier) for hint mode
    static let `default` = HotkeyConfiguration(modifier: .none, key: .f)
}

/// Namespace for UserDefaults keys used throughout the application.
///
/// Centralizing keys here prevents typos and ensures consistency
/// when accessing settings via UserDefaults or @AppStorage.
enum SettingsKey {
    /// Key for storing the hotkey modifier (Option/Command/Control/Shift).
    static let hotkeyModifier = "hotkeyModifier"
    /// Key for storing the hotkey key (Space/Tab/A-Z).
    static let hotkeyKey = "hotkeyKey"
}

extension HotkeyConfiguration {
    /// Loads configuration from UserDefaults, falling back to defaults.
    /// - Parameter defaults: UserDefaults instance to read from. Defaults to `.standard`.
    static func load(from defaults: UserDefaults = .standard) -> HotkeyConfiguration {
        let modifierRaw = defaults.string(forKey: SettingsKey.hotkeyModifier)
            ?? ModifierKey.none.rawValue
        let keyRaw = defaults.string(forKey: SettingsKey.hotkeyKey)
            ?? HotkeyKey.f.rawValue

        let modifier = ModifierKey(rawValue: modifierRaw) ?? .none
        let key = HotkeyKey(rawValue: keyRaw) ?? .f

        return HotkeyConfiguration(modifier: modifier, key: key)
    }

    /// Saves configuration to UserDefaults.
    /// - Parameter defaults: UserDefaults instance to write to. Defaults to `.standard`.
    func save(to defaults: UserDefaults = .standard) {
        defaults.set(modifier.rawValue, forKey: SettingsKey.hotkeyModifier)
        defaults.set(key.rawValue, forKey: SettingsKey.hotkeyKey)
    }
}
