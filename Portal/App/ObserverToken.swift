//
//  ObserverToken.swift
//  Portal
//
//  Created by GPT-5.2 on 2026/01/13.
//

import Foundation

/// A small helper that removes a NotificationCenter block-based observer token on deinit.
final class ObserverToken {
    private let center: NotificationCenter
    private var token: NSObjectProtocol?

    init(center: NotificationCenter = .default, token: NSObjectProtocol) {
        self.center = center
        self.token = token
    }

    func cancel() {
        guard let token else { return }
        center.removeObserver(token)
        self.token = nil
    }

    deinit {
        cancel()
    }
}
