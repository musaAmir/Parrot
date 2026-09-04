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
import os

/// A key binding in the form the event tap needs it, with `CGEventFlags` already
/// resolved so the tap callback never has to translate `NSEvent.ModifierFlags`.
struct KeyBinding: Equatable {
    var keyCode: UInt16
    var flags: CGEventFlags
    var isEnabled: Bool

    func matches(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        isEnabled && keyCode == self.keyCode && flags == self.flags
    }

    static let disabled = KeyBinding(keyCode: 0, flags: [], isEnabled: false)
}

/// Thread-safe snapshot of the current shortcuts.
///
/// The event tap callback runs on its own thread for every keystroke on the
/// system. Reading `@Published` properties off `AudioManager` from there is a
/// data race, and any delay there makes macOS disable the tap outright, so the
/// bindings are copied into this box whenever settings change and the callback
/// only ever reads the copy.
final class ShortcutSnapshot: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var hold: KeyBinding = .disabled
    private var toggle: KeyBinding = .disabled

    func update(hold: KeyBinding, toggle: KeyBinding) {
        os_unfair_lock_lock(&lock)
        self.hold = hold
        self.toggle = toggle
        os_unfair_lock_unlock(&lock)
    }

    func read() -> (hold: KeyBinding, toggle: KeyBinding) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return (hold, toggle)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem?
    var audioManager: AudioManager!
    var permissionManager: PermissionManager!
    var settingsWindow: NSWindow?
    var permissionCheckTimer: Timer?
    var eventTapCreationFailed = false
    var cancellables = Set<AnyCancellable>()
    var launchAtLoginItem: NSMenuItem?

    // Global keyboard shortcut plumbing
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    let shortcutSnapshot = ShortcutSnapshot()

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
        setupShortcutObservers()
        setupGlobalKeyboardShortcut()
        setupEventTapRecovery()
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
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon in
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()
                return appDelegate.handleGlobalKeyEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.shortcuts.error("Failed to create event tap. Accessibility permission is missing.")
            eventTapCreationFailed = true
            return
        }

        eventTap = tap
        eventTapRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), eventTapRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTapCreationFailed = false

        Log.shortcuts.info("Global keyboard shortcuts enabled.")
    }

    /// Turns the tap back on after macOS has switched it off.
    ///
    /// The system disables an event tap whose callback took too long, and again
    /// across some sleep/wake and fast-user-switch transitions. Without this the
    /// shortcuts stop working silently and stay dead until the app is relaunched.
    func reenableEventTapIfNeeded() {
        guard let tap = eventTap else {
            // Never got a tap in the first place - usually a missing permission.
            // Try once more in case it has since been granted.
            setupGlobalKeyboardShortcut()
            return
        }
        guard !CGEvent.tapIsEnabled(tap: tap) else { return }
        Log.shortcuts.notice("Event tap was disabled by the system; re-enabling.")
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func setupEventTapRecovery() {
        // Taps commonly die across sleep/wake and fast user switching.
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                self?.reenableEventTapIfNeeded()
            }
        }
    }

    /// Copies the current shortcut settings into the lock-protected snapshot the
    /// event tap callback reads.
    func publishShortcutSnapshot() {
        func cgFlags(_ modifiers: NSEvent.ModifierFlags) -> CGEventFlags {
            var flags: CGEventFlags = []
            if modifiers.contains(.command) { flags.insert(.maskCommand) }
            if modifiers.contains(.option) { flags.insert(.maskAlternate) }
            if modifiers.contains(.shift) { flags.insert(.maskShift) }
            if modifiers.contains(.control) { flags.insert(.maskControl) }
            return flags
        }

        shortcutSnapshot.update(
            hold: KeyBinding(
                keyCode: audioManager.shortcutKeyCode,
                flags: cgFlags(audioManager.shortcutModifierFlags),
                isEnabled: audioManager.holdModeEnabled
            ),
            toggle: KeyBinding(
                keyCode: audioManager.toggleShortcutKeyCode,
                flags: cgFlags(audioManager.toggleShortcutModifierFlags),
                isEnabled: audioManager.toggleModeEnabled
            )
        )
    }

    func setupShortcutObservers() {
        publishShortcutSnapshot()
        audioManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.publishShortcutSnapshot() }
            .store(in: &cancellables)
    }

    func handleGlobalKeyEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS switches the tap off if this callback is ever too slow, and tells
        // us by delivering one of these two event types. Turning it straight back
        // on is the only thing that keeps the shortcuts alive.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return nil
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) == 1
        let flags = event.flags.intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])

        let (hold, toggle) = shortcutSnapshot.read()

        if hold.matches(keyCode: keyCode, flags: flags) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if type == .keyDown && !isRepeat {
                    self.audioManager.startRecording()
                } else if type == .keyUp {
                    self.audioManager.stopRecordingAndPlayback()
                }
            }
            return nil
        }

        if toggle.matches(keyCode: keyCode, flags: flags) {
            if type == .keyDown && !isRepeat {
                DispatchQueue.main.async { [weak self] in
                    self?.beginToggleShortcutPress()
                }
                return nil
            } else if type == .keyUp {
                DispatchQueue.main.async { [weak self] in
                    self?.endToggleShortcutPress()
                }
                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Toggle shortcut press handling

    /// A tap starts/stops recording; holding past `toggleHoldThreshold` instead
    /// behaves like the hold shortcut, so a long press never leaves a recording
    /// running by accident.
    private static let toggleHoldThreshold: TimeInterval = 1.5

    private func beginToggleShortcutPress() {
        toggleShortcutPressTime = Date()
        toggleShortcutIsInHoldMode = false

        toggleShortcutHoldTimer?.invalidate()
        toggleShortcutHoldTimer = Timer.scheduledTimer(
            withTimeInterval: Self.toggleHoldThreshold, repeats: false
        ) { [weak self] _ in
            guard let self = self else { return }
            Log.shortcuts.debug("Toggle shortcut held past threshold - switching to hold mode")
            self.toggleShortcutIsInHoldMode = true
            self.audioManager.startRecording()
        }
    }

    private func endToggleShortcutPress() {
        toggleShortcutHoldTimer?.invalidate()
        toggleShortcutHoldTimer = nil

        if toggleShortcutIsInHoldMode {
            audioManager.stopRecordingAndPlayback()
            toggleShortcutIsInHoldMode = false
        } else if audioManager.isRecording {
            audioManager.stopRecordingAndPlayback()
        } else {
            audioManager.startRecording()
        }

        toggleShortcutPressTime = nil
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
            Log.app.error("Failed to toggle launch at login: \(error.localizedDescription)")
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
            Log.permissions.info("Accessibility permission already granted")
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
        guard AXIsProcessTrustedWithOptions(options) else { return }

        Log.permissions.info("Accessibility permission granted; enabling shortcuts")
        stopPermissionMonitoring()
        permissionManager.refreshPermissions()

        // The tap can be created now that we are trusted, so there is no longer
        // any reason to relaunch the app out from under the user.
        setupGlobalKeyboardShortcut()
    }
}
