//
//  SettingsView.swift
//  Parrot
//
//  Settings UI with modern macOS sidebar navigation
//

import SwiftUI
import AVFoundation

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case shortcuts = "Shortcuts"
    case audio = "Audio"
    case permissions = "Permissions"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .shortcuts: return "command.square"
        case .audio: return "speaker.wave.2"
        case .permissions: return "lock.shield"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var permissionManager: PermissionManager
    var onClose: () -> Void
    @State private var selectedTab: SettingsTab = .general
    @State private var inputDevices: [AVCaptureDevice] = []
    @State private var outputDevices: [AudioManager.AudioOutputDevice] = []

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            ScrollView {
                VStack(spacing: 20) {
                    switch selectedTab {
                    case .general:
                        GeneralSettingsTab(audioManager: audioManager)
                    case .shortcuts:
                        ShortcutsSettingsTab(audioManager: audioManager)
                    case .audio:
                        AudioSettingsTab(
                            audioManager: audioManager,
                            inputDevices: $inputDevices,
                            outputDevices: $outputDevices
                        )
                    case .permissions:
                        PermissionsSettingsTab(permissionManager: permissionManager)
                    }
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 650, height: 420)
        .onAppear {
            inputDevices = audioManager.getAvailableInputDevices()
            outputDevices = audioManager.getAvailableOutputDevices()
            permissionManager.refreshPermissions()
        }
    }
}

// MARK: - Modern Rounded Section

struct ModernSection<Content: View>: View {
    let header: String?
    let footer: String?
    let content: Content

    init(header: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.header = header
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header = header {
                Text(header)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .padding(.leading, 4)
            }

            VStack(spacing: 0) {
                content
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let footer = footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
    }
}

struct ModernRow<Content: View>: View {
    let content: Content
    let showDivider: Bool

    init(showDivider: Bool = true, @ViewBuilder content: () -> Content) {
        self.showDivider = showDivider
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if showDivider {
                Divider()
                    .padding(.leading, 16)
            }
        }
    }
}

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    @ObservedObject var audioManager: AudioManager

    var body: some View {
        VStack(spacing: 20) {
            ModernSection(header: "Playback") {
                ModernRow {
                    HStack(spacing: 16) {
                        Text("Playback Delay")
                        Slider(value: $audioManager.playbackDelay, in: 0.0...5.0, step: 0.1)
                            .frame(width: 150)
                        Text(String(format: "%.1f s", audioManager.playbackDelay))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 45, alignment: .trailing)
                        Spacer()
                    }
                }

                ModernRow(showDivider: false) {
                    HStack(spacing: 16) {
                        Text("Volume")
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                        Slider(value: $audioManager.playbackVolume, in: 0.0...1.0, step: 0.05)
                            .frame(width: 120)
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                        Text("\(Int(audioManager.playbackVolume * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 45, alignment: .trailing)
                        Spacer()
                    }
                }
            }

            ModernSection(header: "Appearance") {
                ModernRow {
                    HStack {
                        Toggle(isOn: $audioManager.showDockIcon) {
                            Text("Enable")
                        }
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .onChange(of: audioManager.showDockIcon) { _, newValue in
                            NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                        }
                        Text("Show Dock Icon")
                        Spacer()
                    }
                }

                ModernRow {
                    HStack {
                        Toggle(isOn: $audioManager.showPlaybackIndicator) {
                            Text("Enable")
                        }
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        Text("Show Playback Indicator")
                        Spacer()
                    }
                }

                ModernRow(showDivider: false) {
                    HStack {
                        Toggle(isOn: $audioManager.playFeedbackSounds) {
                            Text("Enable")
                        }
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        Text("Play Feedback Sounds")
                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Shortcuts Settings Tab

struct ShortcutsSettingsTab: View {
    @ObservedObject var audioManager: AudioManager

    var body: some View {
        VStack(spacing: 20) {
            ModernSection(
                header: "Hold to Record",
                footer: "Press and hold the shortcut while speaking, release to play back"
            ) {
                ModernRow(showDivider: audioManager.holdModeEnabled) {
                    HStack {
                        Toggle(isOn: $audioManager.holdModeEnabled) {
                            Text("Enable")
                        }
                        .toggleStyle(.checkbox)
                        .labelsHidden()

                        Text("Enable Hold to Record")
                        Spacer()
                    }
                }

                if audioManager.holdModeEnabled {
                    ModernRow(showDivider: false) {
                        HStack(spacing: 50) {
                            Text("Shortcut")
                            ShortcutRecorder(
                                keyCode: $audioManager.shortcutKeyCode,
                                modifierFlags: $audioManager.shortcutModifierFlags
                            )
                            .frame(width: 180, height: 32)
                            Spacer()
                        }
                    }
                }
            }

            ModernSection(
                header: "Toggle to Record",
                footer: "Tap once to start recording, tap again to stop. Hold for 1.5s for hold mode."
            ) {
                ModernRow(showDivider: audioManager.toggleModeEnabled) {
                    HStack {
                        Toggle(isOn: $audioManager.toggleModeEnabled) {
                            Text("Enable")
                        }
                        .toggleStyle(.checkbox)
                        .labelsHidden()

                        Text("Enable Toggle to Record")
                        Spacer()
                    }
                }

                if audioManager.toggleModeEnabled {
                    ModernRow(showDivider: false) {
                        HStack(spacing: 50) {
                            Text("Shortcut")
                            ShortcutRecorder(
                                keyCode: $audioManager.toggleShortcutKeyCode,
                                modifierFlags: $audioManager.toggleShortcutModifierFlags
                            )
                            .frame(width: 180, height: 32)
                            Spacer()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Audio Settings Tab

struct AudioSettingsTab: View {
    @ObservedObject var audioManager: AudioManager
    @Binding var inputDevices: [AVCaptureDevice]
    @Binding var outputDevices: [AudioManager.AudioOutputDevice]

    private let pickerWidth: CGFloat = 220

    var body: some View {
        VStack(spacing: 20) {
            ModernSection(header: "Input Device") {
                ModernRow(showDivider: false) {
                    HStack {
                        Picker("Microphone", selection: $audioManager.selectedInputDevice) {
                            Text("System Default").tag(nil as AVCaptureDevice?)
                            Divider()
                            ForEach(inputDevices, id: \.uniqueID) { device in
                                Text(device.localizedName).tag(device as AVCaptureDevice?)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(minWidth: pickerWidth, maxWidth: pickerWidth)
                        Spacer()
                    }
                }
            }

            ModernSection(header: "Output Device") {
                ModernRow(showDivider: false) {
                    HStack {
                        Picker("Speaker", selection: $audioManager.selectedOutputDeviceID) {
                            Text("System Default").tag(nil as String?)
                            Divider()
                            ForEach(outputDevices) { device in
                                Text(device.name).tag(device.uid as String?)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(minWidth: pickerWidth, maxWidth: pickerWidth)
                        Spacer()
                    }
                }
            }

            ModernSection {
                ModernRow(showDivider: false) {
                    HStack {
                        Button("Refresh Devices") {
                            inputDevices = audioManager.getAvailableInputDevices()
                            outputDevices = audioManager.getAvailableOutputDevices()
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Permissions Settings Tab

struct PermissionsSettingsTab: View {
    @ObservedObject var permissionManager: PermissionManager

    var body: some View {
        VStack(spacing: 20) {
            ModernSection(
                header: "Microphone",
                footer: "Required to record your voice"
            ) {
                ModernRow(showDivider: false) {
                    Label("Microphone Access", systemImage: "mic.fill")
                    Spacer()
                    PermissionStatusView(status: permissionManager.microphoneStatus)
                    if permissionManager.microphoneStatus != .granted {
                        Button("Open Settings") {
                            permissionManager.openSystemPreferences(for: "microphone")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            ModernSection(
                header: "Accessibility",
                footer: "Required for global keyboard shortcuts to work"
            ) {
                ModernRow(showDivider: false) {
                    Label("Accessibility Access", systemImage: "hand.raised.fill")
                    Spacer()
                    PermissionStatusView(status: permissionManager.accessibilityStatus)
                    if permissionManager.accessibilityStatus != .granted {
                        Button("Open Settings") {
                            permissionManager.openSystemPreferences(for: "accessibility")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            ModernSection {
                ModernRow(showDivider: false) {
                    Spacer()
                    Button("Refresh Status") {
                        permissionManager.refreshPermissions()
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Supporting Views

struct PermissionStatusView: View {
    let status: PermissionManager.PermissionStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(status.displayText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    var statusColor: Color {
        switch status {
        case .granted: return .green
        case .denied: return .red
        case .notDetermined: return .orange
        }
    }
}
