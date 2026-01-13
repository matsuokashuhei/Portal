//
//  AppNotificationBindingsTests.swift
//  PortalTests
//
//  Created by GPT-5.2 on 2026/01/13.
//

import AppKit
import XCTest
@testable import Portal

final class AppNotificationBindingsTests: XCTestCase {
    func testStartMapsNotificationsToEvents() {
        let center = NotificationCenter()
        let bindings = AppNotificationBindings(center: center)

        var received: [AppNotificationBindings.Event] = []
        let exp = expectation(description: "receive events")
        exp.expectedFulfillmentCount = 4

        bindings.start { event in
            received.append(event)
            exp.fulfill()
        }

        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        center.post(name: .hotkeyConfigurationChanged, object: nil)
        center.post(name: .excludedAppsConfigurationChanged, object: nil)
        center.post(name: .openSettings, object: nil)

        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(
            received,
            [
                .applicationDidBecomeActive,
                .hotkeyConfigurationChanged,
                .excludedAppsConfigurationChanged,
                .openSettingsRequested,
            ]
        )
    }

    func testStopRemovesObservers() {
        let center = NotificationCenter()
        let bindings = AppNotificationBindings(center: center)

        let inverted = expectation(description: "no further events after stop")
        inverted.isInverted = true

        bindings.start { _ in
            inverted.fulfill()
        }
        bindings.stop()

        center.post(name: .openSettings, object: nil)
        wait(for: [inverted], timeout: 0.2)
    }
}

