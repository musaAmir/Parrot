//
//  SettingsView.swift
//  Parrot
//
//  Settings UI with modern macOS styling
//

import SwiftUI
import AVFoundation

struct SettingsView: View {
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var permissionManager: PermissionManager
    var onClose: () -> Void
    @State private var inputDevices: [AVCaptureDevice] = []
    @State private var outputDevices: [AudioManager.AudioOutputDevice] = []
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab(audioManager: audioManager)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(0)

            ShortcutsSettingsTab(audioManager: audioManager)
                .tabItem {
                    Label("Shortcuts", systemImage: "command.square")
                }
                .tag(1)

            AudioSettingsTab(
                audioManager: audioManager,
                inputDevices: $inputDevices,
                outputDevices: $outputDevices
            )
                .tabItem {
                    Label("Audio", systemImage: "speaker.wave.2")
                }
                .tag(2)

            PermissionsSettingsTab(permissionManager: permissionManager)
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }
                .tag(3)
        }
        .frame(width: 500, height: 400)
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
            } header: {
                Text("Playback")
            } footer: {
                Text("Time to wait before playing back your recording")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Volume") {
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(.secondary)
                        Slider(value: $audioManager.playbackVolume, in: 0.0...1.0, step: 0.05)
                            .frame(width: 140)
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(.secondary)
                        Text("\(Int(audioManager.playbackVolume * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
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
