//
//  Command.swift
//  Portal
//
//  Created by Claude on 2025/12/30.
//

import Foundation

enum CommandCategory: String, CaseIterable {
    case menu
    case file
    case system
}

protocol Command: Identifiable {
    var id: String { get }
    var title: String { get }
    var subtitle: String? { get }
    var category: CommandCategory { get }
    var icon: String? { get }

    func execute() async throws
}
