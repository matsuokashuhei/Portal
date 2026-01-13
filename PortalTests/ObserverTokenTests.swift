//
//  ObserverTokenTests.swift
//  PortalTests
//
//  Created by GPT-5.2 on 2026/01/13.
//

import XCTest
@testable import Portal

final class ObserverTokenTests: XCTestCase {
    func testCancelRemovesObserver() {
        let center = NotificationCenter()
        let name = Notification.Name("ObserverTokenTests.cancel")

        var callCount = 0
        let token = center.addObserver(forName: name, object: nil, queue: nil) { _ in
            callCount += 1
        }

        let observerToken = ObserverToken(center: center, token: token)

        center.post(name: name, object: nil)
        XCTAssertEqual(callCount, 1)

        observerToken.cancel()
        center.post(name: name, object: nil)
        XCTAssertEqual(callCount, 1, "After cancel(), observer should not be invoked.")
    }

    func testDeinitRemovesObserver() {
        let center = NotificationCenter()
        let name = Notification.Name("ObserverTokenTests.deinit")

        var callCount = 0
        let token = center.addObserver(forName: name, object: nil, queue: nil) { _ in
            callCount += 1
        }

        var observerToken: ObserverToken? = ObserverToken(center: center, token: token)
        center.post(name: name, object: nil)
        XCTAssertEqual(callCount, 1)

        observerToken = nil

        center.post(name: name, object: nil)
        XCTAssertEqual(callCount, 1, "After deinit, observer should not be invoked.")
    }
}
