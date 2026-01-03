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
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem?
    var audioManager: AudioManager!
    var permissionManager: PermissionManager!
    var settingsWindow: NSWindow?
    var permissionCheckTimer: Timer?
    var eventTapCreationFailed = false
    var cancellables = Set<AnyCancellable>()
    var launchAtLoginItem: NSMenuItem?

    // Indicator windows
    var recordingIndicatorWindow: RecordingIndicatorWindow?
    var playbackIndicatorWindow: PlaybackIndicatorWindow?
    var overlayDismissTimer: Timer?
    var playbackOverlayShown = false

    // Smart shortcut state tracking
    var toggleShortcutPressTime: Date?
    var toggleShortcutHoldTimer: Timer?
    var toggleShortcutIsInHoldMode = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        audioManager = AudioManager()
        permissionManager = PermissionManager()

        // Apply appearance settings
        applyDockIconSetting()
        if audioManager.showMenuBarIcon {
            setupMenuBar()
        }

        setupIndicatorWindows()
        setupRecordingObservers()
        setupAppearanceObservers()
        setupGlobalKeyboardShortcut()
        requestPermissions()

        if eventTapCreationFailed {
            startPermissionMonitoring()
        }
    }

    func applyDockIconSetting() {
        NSApp.setActivationPolicy(audioManager.showDockIcon ? .regular : .accessory)
    }

    func setupAppearanceObservers() {
        // Observe dock icon changes
        audioManager.$showDockIcon
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showDock in
                guard let self = self else { return }
                // Ensure at least one icon is visible
                if !showDock && !self.audioManager.showMenuBarIcon {
                    self.audioManager.showMenuBarIcon = true
                }
                NSApp.setActivationPolicy(showDock ? .regular : .accessory)
            }
            .store(in: &cancellables)

        // Observe menu bar icon changes
        audioManager.$showMenuBarIcon
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showMenuBar in
                guard let self = self else { return }
                // Ensure at least one icon is visible
                if !showMenuBar && !self.audioManager.showDockIcon {
                    self.audioManager.showDockIcon = true
                }
                if showMenuBar && self.statusItem == nil {
                    self.setupMenuBar()
                } else if !showMenuBar && self.statusItem != nil {
                    NSStatusBar.system.removeStatusItem(self.statusItem!)
                    self.statusItem = nil
                }
            }
            .store(in: &cancellables)
    }

    func setupIndicatorWindows() {
        recordingIndicatorWindow = RecordingIndicatorWindow(appDelegate: self)
        playbackIndicatorWindow = PlaybackIndicatorWindow(audioManager: audioManager)
        playbackIndicatorWindow?.onReplay = { [weak self] in
            self?.resetOverlayDismissTimer()
        }
    }

    func resetOverlayDismissTimer() {
        overlayDismissTimer?.invalidate()
        overlayDismissTimer = nil
    }

    func startOverlayDismissTimer() {
        // Only start timer if overlay was shown
        guard playbackOverlayShown else { return }

        overlayDismissTimer?.invalidate()
        overlayDismissTimer = Timer.scheduledTimer(withTimeInterval: audioManager.overlayDismissDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.playbackIndicatorWindow?.hide()
            self.playbackOverlayShown = false
            self.overlayDismissTimer = nil
        }
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
                    self.resetOverlayDismissTimer()
                    self.playbackIndicatorWindow?.show()
                    self.playbackOverlayShown = true
                } else if !isPlaying {
                    // Playback finished - start the dismiss timer
                    self.startOverlayDismissTimer()
                }
            }
            .store(in: &cancellables)
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform.badge.microphone", accessibilityDescription: "Parrot")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())

        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem?.target = self
        updateLaunchAtLoginState()
        menu.addItem(launchAtLoginItem!)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ application: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Open settings when dock icon is clicked
        openSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up all timers to prevent energy usage
        stopPermissionMonitoring()
        overlayDismissTimer?.invalidate()
        overlayDismissTimer = nil
        toggleShortcutHoldTimer?.invalidate()
        toggleShortcutHoldTimer = nil
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
        // Temporarily switch to regular app to show window properly
        if NSApp.activationPolicy() == .accessory {
            NSApp.setActivationPolicy(.regular)
        }

        if settingsWindow == nil {
            let settingsView = SettingsView(
                audioManager: audioManager,
                permissionManager: permissionManager,
                onClose: { [weak self] in
                    self?.closeSettingsWindow()
                }
            )
            let hostingController = NSHostingController(rootView: settingsView)

            settingsWindow = NSWindow(contentViewController: hostingController)
            settingsWindow?.title = "Parrot Settings"
            settingsWindow?.styleMask = [.titled, .closable, .miniaturizable]
            settingsWindow?.setContentSize(NSSize(width: 650, height: 420))
            settingsWindow?.center()
            settingsWindow?.isReleasedWhenClosed = false
            settingsWindow?.delegate = self
        }

        permissionManager.refreshPermissions()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeSettingsWindow() {
        settingsWindow?.close()
        settingsWindow = nil
        // Restore accessory mode if dock icon should be hidden
        if !audioManager.showDockIcon {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Check if it's the settings window closing
        if let window = notification.object as? NSWindow, window == settingsWindow {
            settingsWindow = nil
            // Restore accessory mode if dock icon should be hidden
            if !audioManager.showDockIcon {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            print("Failed to toggle launch at login: \(error)")
        }
        updateLaunchAtLoginState()
    }

    func updateLaunchAtLoginState() {
        let isEnabled = SMAppService.mainApp.status == .enabled
        launchAtLoginItem?.state = isEnabled ? .on : .off
    }

    // MARK: - Permission Monitoring

    func startPermissionMonitoring() {
        // Check if already granted before starting timer
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        if AXIsProcessTrustedWithOptions(options) {
            print("Accessibility permission already granted")
            return
        }

        // Check every 3 seconds instead of every 1 second to reduce energy usage
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.checkAccessibilityPermissionAndRestart()
        }
    }

    func stopPermissionMonitoring() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }

    func checkAccessibilityPermissionAndRestart() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)

        if accessEnabled {
            print("Accessibility permission granted! Restarting app...")
            stopPermissionMonitoring()
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
