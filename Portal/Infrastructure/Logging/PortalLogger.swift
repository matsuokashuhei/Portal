//
//  PortalLogger.swift
//  Portal
//
//  Created by GPT-5.2 on 2026/01/18.
//

import Logging

enum PortalLogger {
    private static var isConfigured = false

    static func configure() {
        guard !isConfigured else { return }

        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = defaultLogLevel()
            return handler
        }

        isConfigured = true
    }

    static func make(_ label: String, category: String? = nil) -> Logger {
        let fullLabel: String
        if let category, !category.isEmpty {
            fullLabel = "\(label).\(category)"
        } else {
            fullLabel = label
        }

        configure()
        return Logger(label: fullLabel)
    }

    private static func defaultLogLevel() -> Logger.Level {
//        #if DEBUG
//        return .debug
//        #else
//        return .info
//        #endif
        .debug
    }
}
