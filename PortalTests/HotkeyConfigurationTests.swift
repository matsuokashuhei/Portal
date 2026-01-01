//
//  HotkeyConfigurationTests.swift
//  PortalTests
//
//  Created by Claude Code on 2026/01/01.
//

import AppKit
import Testing
@testable import Portal

struct HotkeyConfigurationTests {

    // MARK: - Test Helper

    /// Creates a unique test suite name for each test run to avoid parallel test conflicts.
    /// Uses UUID to ensure complete isolation between concurrent test processes.
    private func withIsolatedDefaults(_ body: (UserDefaults) -> Void) {
        let testSuiteName = "com.portal.test.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: testSuiteName)!

        defer {
            // Clean up the test suite
            testDefaults.removePersistentDomain(forName: testSuiteName)
        }

        body(testDefaults)
    }

    // MARK: - Default Configuration Tests

    @Test
    func testDefaultConfiguration() {
        let config = HotkeyConfiguration.default

        #expect(config.modifier == .option)
        #expect(config.key == .space)
    }

    // MARK: - ModifierKey Tests

    @Test
    func testModifierKeyEventFlags() {
        #expect(ModifierKey.option.eventModifier == .option)
        #expect(ModifierKey.command.eventModifier == .command)
        #expect(ModifierKey.control.eventModifier == .control)
        #expect(ModifierKey.shift.eventModifier == .shift)
    }

    @Test
    func testModifierKeyCGEventMasks() {
        #expect(ModifierKey.option.cgEventMask == .maskAlternate)
        #expect(ModifierKey.command.cgEventMask == .maskCommand)
        #expect(ModifierKey.control.cgEventMask == .maskControl)
        #expect(ModifierKey.shift.cgEventMask == .maskShift)
    }

    @Test
    func testModifierKeySymbols() {
        #expect(ModifierKey.option.symbol == "⌥")
        #expect(ModifierKey.command.symbol == "⌘")
        #expect(ModifierKey.control.symbol == "⌃")
        #expect(ModifierKey.shift.symbol == "⇧")
    }

    @Test
    func testModifierKeyRawValues() {
        #expect(ModifierKey.option.rawValue == "Option")
        #expect(ModifierKey.command.rawValue == "Command")
        #expect(ModifierKey.control.rawValue == "Control")
        #expect(ModifierKey.shift.rawValue == "Shift")
    }

    @Test
    func testModifierKeyCaseIterable() {
        let allCases = ModifierKey.allCases

        #expect(allCases.count == 4)
        #expect(allCases.contains(.option))
        #expect(allCases.contains(.command))
        #expect(allCases.contains(.control))
        #expect(allCases.contains(.shift))
    }

    // MARK: - HotkeyKey Tests

    @Test
    func testHotkeyKeyCommonKeyCodes() {
        #expect(HotkeyKey.space.keyCode == 49)
        #expect(HotkeyKey.tab.keyCode == 48)
        #expect(HotkeyKey.a.keyCode == 0)
        #expect(HotkeyKey.z.keyCode == 6)
    }

    @Test
    func testHotkeyKeyAllLettersPresent() {
        let allCases = HotkeyKey.allCases
        let letters = "abcdefghijklmnopqrstuvwxyz".map { String($0).uppercased() }

        for letter in letters {
            let hasLetter = allCases.contains { $0.rawValue == letter }
            #expect(hasLetter, "Missing letter key: \(letter)")
        }
    }

    @Test
    func testHotkeyKeyCaseIterable() {
        let allCases = HotkeyKey.allCases

        // 26 letters + space + tab = 28
        #expect(allCases.count == 28)
        #expect(allCases.contains(.space))
        #expect(allCases.contains(.tab))
    }

    // MARK: - Persistence Tests

    @Test
    func testSaveAndLoad() {
        withIsolatedDefaults { defaults in
            // Save a custom configuration
            let config = HotkeyConfiguration(modifier: .command, key: .p)
            config.save(to: defaults)

            // Load and verify
            let loaded = HotkeyConfiguration.load(from: defaults)
            #expect(loaded.modifier == .command)
            #expect(loaded.key == .p)
        }
    }

    @Test
    func testLoadWithMissingValuesReturnsDefaults() {
        withIsolatedDefaults { defaults in
            // defaults is empty by default, so just load
            let loaded = HotkeyConfiguration.load(from: defaults)
            #expect(loaded.modifier == .option)
            #expect(loaded.key == .space)
        }
    }

    @Test
    func testLoadWithInvalidValuesReturnsDefaults() {
        withIsolatedDefaults { defaults in
            // Set invalid values
            defaults.set("InvalidModifier", forKey: SettingsKey.hotkeyModifier)
            defaults.set("InvalidKey", forKey: SettingsKey.hotkeyKey)

            // Load and verify defaults are returned
            let loaded = HotkeyConfiguration.load(from: defaults)
            #expect(loaded.modifier == .option)
            #expect(loaded.key == .space)
        }
    }

    // MARK: - Equality Tests

    @Test
    func testEquality() {
        let config1 = HotkeyConfiguration(modifier: .option, key: .space)
        let config2 = HotkeyConfiguration(modifier: .option, key: .space)
        let config3 = HotkeyConfiguration(modifier: .command, key: .space)

        #expect(config1 == config2)
        #expect(config1 != config3)
    }
}
