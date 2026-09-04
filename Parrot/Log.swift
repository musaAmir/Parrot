//
//  Log.swift
//  Parrot
//
//  Unified logging categories. Replaces print(), which shipped in Release builds
//  and wrote to stdout where nobody could see it.
//

import Foundation
import os

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.parrot.app"

    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let shortcuts = Logger(subsystem: subsystem, category: "shortcuts")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let app = Logger(subsystem: subsystem, category: "app")
}
