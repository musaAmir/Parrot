//
//  SettingsView.swift
//  Parrot
//
//  Settings UI for delay, shortcuts, audio devices, and permissions
//

import SwiftUI
import AVFoundation

struct SettingsView: View {
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var permissionManager: PermissionManager
    var onClose: () -> Void
    @State private var inputDevices: [AVCaptureDevice] = []
    @State private var outputDevices: [AudioManager.AudioOutputDevice] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                Text("Parrot Settings")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.bottom, 8)

                // Playback Delay
                GroupBox("Playback Delay") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Slider(value: $audioManager.playbackDelay, in: 0.0...5.0, step: 0.1)
                            Text(String(format: "%.1f s", audioManager.playbackDelay))
                                .frame(width: 50)
                                .monospacedDigit()
                        }
                        Text("Time between recording and playback")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // Hold to Record
                GroupBox("Hold to Record") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Enable Hold to Record", isOn: $audioManager.holdModeEnabled)
                        if audioManager.holdModeEnabled {
                            Text("Shortcut: ⌘⇧Z (press and hold while speaking)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Toggle to Record
                GroupBox("Toggle to Record") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Enable Toggle to Record", isOn: $audioManager.toggleModeEnabled)
                        if audioManager.toggleModeEnabled {
                            Text("Shortcut: ⌘⇧T (tap to start/stop)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Playback Volume
                GroupBox("Playback Volume") {
                    HStack {
                        Image(systemName: "speaker.fill")
                        Slider(value: $audioManager.playbackVolume, in: 0.0...1.0, step: 0.05)
                        Image(systemName: "speaker.wave.3.fill")
                        Text(String(format: "%d%%", Int(audioManager.playbackVolume * 100)))
                            .frame(width: 45)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)
                }

                // Audio Input Device
                GroupBox("Audio Input") {
                    Picker("Microphone", selection: $audioManager.selectedInputDevice) {
                        Text("Default").tag(nil as AVCaptureDevice?)
                        ForEach(inputDevices, id: \.uniqueID) { device in
                            Text(device.localizedName).tag(device as AVCaptureDevice?)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Audio Output Device
                GroupBox("Audio Output") {
                    Picker("Speaker", selection: $audioManager.selectedOutputDeviceID) {
                        Text("Default").tag(nil as String?)
                        ForEach(outputDevices) { device in
                            Text(device.name).tag(device.uid as String?)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Permissions
                GroupBox("Permissions") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "mic.fill")
                            Text("Microphone")
                            Spacer()
                            PermissionBadge(status: permissionManager.microphoneStatus)
                            if permissionManager.microphoneStatus != .granted {
                                Button("Grant") {
                                    permissionManager.openSystemPreferences(for: "microphone")
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        Divider()

                        HStack {
                            Image(systemName: "hand.raised.fill")
                            Text("Accessibility")
                            Spacer()
                            PermissionBadge(status: permissionManager.accessibilityStatus)
                            if permissionManager.accessibilityStatus != .granted {
                                Button("Grant") {
                                    permissionManager.openSystemPreferences(for: "accessibility")
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        Text("Accessibility is required for global keyboard shortcuts")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // Options
                GroupBox("Options") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Show Dock Icon", isOn: $audioManager.showDockIcon)
                            .onChange(of: audioManager.showDockIcon) { newValue in
                                NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                            }
                        Toggle("Show Playback Indicator", isOn: $audioManager.showPlaybackIndicator)
                        Toggle("Play Feedback Sounds", isOn: $audioManager.playFeedbackSounds)
                    }
                    .padding(.vertical, 4)
                }

                // Buttons
                HStack {
                    Button("Refresh") {
                        permissionManager.refreshPermissions()
                        inputDevices = audioManager.getAvailableInputDevices()
                        outputDevices = audioManager.getAvailableOutputDevices()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Save & Close") {
                        audioManager.saveSettings()
                        onClose()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .frame(width: 450, height: 700)
        .onAppear {
            inputDevices = audioManager.getAvailableInputDevices()
            outputDevices = audioManager.getAvailableOutputDevices()
            permissionManager.refreshPermissions()
        }
    }
}

struct PermissionBadge: View {
    let status: PermissionManager.PermissionStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(status.color))
                .frame(width: 8, height: 8)
            Text(status.displayText)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(status.color).opacity(0.15))
        .cornerRadius(8)
    }
}
