//
//  ParrotApp.swift
//  Parrot
//
//  macOS menubar app that records audio and plays it back with a configurable delay.
//

import SwiftUI

@main
struct ParrotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
