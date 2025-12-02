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
            Group {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 600, height: 400)
        .onAppear {
            inputDevices = audioManager.getAvailableInputDevices()
            outputDevices = audioManager.getAvailableOutputDevices()
            permissionManager.refreshPermissions()
        }
    }
}

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    @ObservedObject var audioManager: AudioManager

    var body: some View {
        Form {
            Section {
                LabeledContent("Playback Delay") {
                    HStack(spacing: 12) {
                        Slider(value: $audioManager.playbackDelay, in: 0.0...5.0, step: 0.1)
                            .frame(width: 180)
                        Text(String(format: "%.1f s", audioManager.playbackDelay))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 45, alignment: .trailing)
                    }
                }

                LabeledContent("Volume") {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                        Slider(value: $audioManager.playbackVolume, in: 0.0...1.0, step: 0.05)
                            .frame(width: 140)
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                        Text("\(Int(audioManager.playbackVolume * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            } header: {
                Text("Playback")
            }

            Section("Appearance") {
                Toggle("Show Dock Icon", isOn: $audioManager.showDockIcon)
                    .onChange(of: audioManager.showDockIcon) { _, newValue in
                        NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                    }

                Toggle("Show Playback Indicator", isOn: $audioManager.showPlaybackIndicator)

                Toggle("Play Feedback Sounds", isOn: $audioManager.playFeedbackSounds)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("General")
    }
}

// MARK: - Shortcuts Settings Tab

struct ShortcutsSettingsTab: View {
    @ObservedObject var audioManager: AudioManager

    var body: some View {
        Form {
            Section {
                Toggle("Enable Hold to Record", isOn: $audioManager.holdModeEnabled)

                if audioManager.holdModeEnabled {
                    LabeledContent("Shortcut") {
                        ShortcutRecorder(
                            keyCode: $audioManager.shortcutKeyCode,
                            modifierFlags: $audioManager.shortcutModifierFlags
                        )
                        .frame(width: 180, height: 36)
                    }
                }
            } header: {
                Text("Hold to Record")
            } footer: {
                Text("Press and hold the shortcut while speaking, release to play back")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Enable Toggle to Record", isOn: $audioManager.toggleModeEnabled)

                if audioManager.toggleModeEnabled {
                    LabeledContent("Shortcut") {
                        ShortcutRecorder(
                            keyCode: $audioManager.toggleShortcutKeyCode,
                            modifierFlags: $audioManager.toggleShortcutModifierFlags
                        )
                        .frame(width: 180, height: 36)
                    }
                }
            } header: {
                Text("Toggle to Record")
            } footer: {
                Text("Tap once to start recording, tap again to stop. Hold for 1.5s for hold mode.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Shortcuts")
    }
}

// MARK: - Audio Settings Tab

struct AudioSettingsTab: View {
    @ObservedObject var audioManager: AudioManager
    @Binding var inputDevices: [AVCaptureDevice]
    @Binding var outputDevices: [AudioManager.AudioOutputDevice]

    var body: some View {
        Form {
            Section("Input Device") {
                Picker("Microphone", selection: $audioManager.selectedInputDevice) {
                    Text("System Default").tag(nil as AVCaptureDevice?)
                    Divider()
                    ForEach(inputDevices, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(device as AVCaptureDevice?)
                    }
                }
                .labelsHidden()
            }

            Section("Output Device") {
                Picker("Speaker", selection: $audioManager.selectedOutputDeviceID) {
                    Text("System Default").tag(nil as String?)
                    Divider()
                    ForEach(outputDevices) { device in
                        Text(device.name).tag(device.uid as String?)
                    }
                }
                .labelsHidden()
            }

            Section {
                Button("Refresh Devices") {
                    inputDevices = audioManager.getAvailableInputDevices()
                    outputDevices = audioManager.getAvailableOutputDevices()
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Audio")
    }
}

// MARK: - Permissions Settings Tab

struct PermissionsSettingsTab: View {
    @ObservedObject var permissionManager: PermissionManager

    var body: some View {
        Form {
            Section {
                HStack {
                    Label("Microphone", systemImage: "mic.fill")
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
            } footer: {
                Text("Required to record your voice")
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Label("Accessibility", systemImage: "hand.raised.fill")
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
            } footer: {
                Text("Required for global keyboard shortcuts to work")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Refresh Status") {
                    permissionManager.refreshPermissions()
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Permissions")
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
