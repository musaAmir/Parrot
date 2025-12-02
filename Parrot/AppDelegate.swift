//
//  AppDelegate.swift
//  Parrot
//
//  Main application delegate managing menubar, shortcuts, and recording
//

import Cocoa
import SwiftUI
import Carbon.HIToolbox
import AVFoundation
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var audioManager: AudioManager!
    var permissionManager: PermissionManager!
    var settingsWindow: NSWindow?
    var permissionCheckTimer: Timer?
    var eventTapCreationFailed = false
    var cancellables = Set<AnyCancellable>()

    // Indicator windows
    var recordingIndicatorWindow: RecordingIndicatorWindow?
    var playbackIndicatorWindow: PlaybackIndicatorWindow?

    // Smart shortcut state tracking
    var toggleShortcutPressTime: Date?
    var toggleShortcutHoldTimer: Timer?
    var toggleShortcutIsInHoldMode = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        audioManager = AudioManager()
        permissionManager = PermissionManager()
        setupIndicatorWindows()
        setupRecordingObservers()
        setupGlobalKeyboardShortcut()
        requestPermissions()

        if eventTapCreationFailed {
            startPermissionMonitoring()
        }
    }

    func setupIndicatorWindows() {
        recordingIndicatorWindow = RecordingIndicatorWindow(appDelegate: self)
        playbackIndicatorWindow = PlaybackIndicatorWindow(audioManager: audioManager)
    }

    func setupRecordingObservers() {
        // Observe recording state changes
        audioManager.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording in
                if isRecording {
                    self?.recordingIndicatorWindow?.show()
                } else {
                    self?.recordingIndicatorWindow?.hide()
                }
            }
            .store(in: &cancellables)

        // Observe playback state changes
        audioManager.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                guard let self = self else { return }
                if isPlaying && self.audioManager.showPlaybackIndicator {
                    self.playbackIndicatorWindow?.show()
                } else {
                    self.playbackIndicatorWindow?.hide()
                }
            }
            .store(in: &cancellables)
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Parrot")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ application: NSApplication) -> Bool {
        return false
    }

    func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async { [weak self] in
                self?.permissionManager.microphoneStatus = granted ? .granted : .denied
                if !granted {
                    self?.showPermissionAlert(for: "Microphone")
                }
            }
        }
        permissionManager.checkAccessibilityPermission()
    }

    func showPermissionAlert(for permission: String) {
        let alert = NSAlert()
        alert.messageText = "\(permission) Permission Required"
        alert.informativeText = "Parrot needs \(permission.lowercased()) access to function properly. Please grant permission in System Settings."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            permissionManager.openSystemPreferences(for: permission.lowercased())
        }
    }

    func setupGlobalKeyboardShortcut() {
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: CGEventTapOptions(rawValue: 0)!,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon in
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()
                return appDelegate.handleGlobalKeyEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("ERROR: Failed to create event tap. Grant Accessibility permission in System Settings.")
            eventTapCreationFailed = true
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        print("Global keyboard shortcut enabled.")
    }

    func handleGlobalKeyEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .keyDown || type == .keyUp {
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) == 1

            let relevantFlags = flags.intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])

            // Check for Hold to Record shortcut
            var holdRequiredModifiers: CGEventFlags = []
            if audioManager.shortcutModifierFlags.contains(.command) { holdRequiredModifiers.insert(.maskCommand) }
            if audioManager.shortcutModifierFlags.contains(.option) { holdRequiredModifiers.insert(.maskAlternate) }
            if audioManager.shortcutModifierFlags.contains(.shift) { holdRequiredModifiers.insert(.maskShift) }
            if audioManager.shortcutModifierFlags.contains(.control) { holdRequiredModifiers.insert(.maskControl) }

            let isHoldShortcut = keyCode == audioManager.shortcutKeyCode && relevantFlags == holdRequiredModifiers

            // Check for Toggle to Record shortcut
            var toggleRequiredModifiers: CGEventFlags = []
            if audioManager.toggleShortcutModifierFlags.contains(.command) { toggleRequiredModifiers.insert(.maskCommand) }
            if audioManager.toggleShortcutModifierFlags.contains(.option) { toggleRequiredModifiers.insert(.maskAlternate) }
            if audioManager.toggleShortcutModifierFlags.contains(.shift) { toggleRequiredModifiers.insert(.maskShift) }
            if audioManager.toggleShortcutModifierFlags.contains(.control) { toggleRequiredModifiers.insert(.maskControl) }

            let isToggleShortcut = keyCode == audioManager.toggleShortcutKeyCode && relevantFlags == toggleRequiredModifiers

            // Handle Hold to Record mode
            if isHoldShortcut && audioManager.holdModeEnabled {
                DispatchQueue.main.async { [weak self] in
                    if type == .keyDown && !isRepeat {
                        print("Hold shortcut - starting recording")
                        self?.audioManager.startRecording()
                    } else if type == .keyUp {
                        print("Hold shortcut released - stopping recording")
                        self?.audioManager.stopRecordingAndPlayback()
                    }
                }
                return nil
            }

            // Handle Toggle to Record mode
            if isToggleShortcut && audioManager.toggleModeEnabled {
                if type == .keyDown && !isRepeat {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }

                        self.toggleShortcutPressTime = Date()
                        self.toggleShortcutIsInHoldMode = false

                        self.toggleShortcutHoldTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                            guard let self = self else { return }
                            print("Toggle shortcut held for 1.5s - switching to hold mode")
                            self.toggleShortcutIsInHoldMode = true
                            self.audioManager.startRecording()
                        }
                    }
                    return nil

                } else if type == .keyUp {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }

                        self.toggleShortcutHoldTimer?.invalidate()
                        self.toggleShortcutHoldTimer = nil

                        if self.toggleShortcutIsInHoldMode {
                            print("Toggle shortcut (hold mode) released - stopping recording")
                            self.audioManager.stopRecordingAndPlayback()
                            self.toggleShortcutIsInHoldMode = false
                        } else {
                            if self.audioManager.isRecording {
                                print("Toggle shortcut (quick tap) - stopping recording")
                                self.audioManager.stopRecordingAndPlayback()
                            } else {
                                print("Toggle shortcut (quick tap) - starting recording")
                                self.audioManager.startRecording()
                            }
                        }

                        self.toggleShortcutPressTime = nil
                    }
                    return nil
                }
            }
        }

        return Unmanaged.passRetained(event)
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView(
                audioManager: audioManager,
                permissionManager: permissionManager,
                onClose: { [weak self] in
                    self?.settingsWindow?.close()
                    self?.settingsWindow = nil
                }
            )
            let hostingController = NSHostingController(rootView: settingsView)

            settingsWindow = NSWindow(contentViewController: hostingController)
            settingsWindow?.title = "Parrot Settings"
            settingsWindow?.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            settingsWindow?.titlebarAppearsTransparent = true
            settingsWindow?.setContentSize(NSSize(width: 650, height: 420))
            settingsWindow?.center()
            settingsWindow?.isReleasedWhenClosed = false
            settingsWindow?.backgroundColor = .windowBackgroundColor

            // Apply rounded corners
            if let contentView = settingsWindow?.contentView {
                contentView.wantsLayer = true
                contentView.layer?.cornerRadius = 12
                contentView.layer?.masksToBounds = true
            }
        }

        permissionManager.refreshPermissions()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Permission Monitoring

    func startPermissionMonitoring() {
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkAccessibilityPermissionAndRestart()
        }
    }

    func checkAccessibilityPermissionAndRestart() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)

        if accessEnabled {
            print("Accessibility permission granted! Restarting app...")
            permissionCheckTimer?.invalidate()
            permissionCheckTimer = nil
            restartApp()
        }
    }

    func restartApp() {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [Bundle.main.bundlePath]
        task.launch()

        NSApp.terminate(nil)
    }
}
