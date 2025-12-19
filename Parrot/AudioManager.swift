//
//  AudioManager.swift
//  Parrot
//
//  Handles audio recording, playback, and user settings
//

import AVFoundation
import AppKit
import Combine
import CoreAudio

class AudioManager: ObservableObject {
    @Published var playbackDelay: Double = 0.5
    @Published var selectedInputDevice: AVCaptureDevice?
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var playbackProgress: Double = 0.0

    // Enable/disable flags for each mode
    @Published var holdModeEnabled: Bool = true
    @Published var toggleModeEnabled: Bool = false

    // Hold to record shortcut
    @Published var shortcutKeyCode: UInt16 = 6  // Z key
    @Published var shortcutModifierFlags: NSEvent.ModifierFlags = [.command, .shift]

    // Toggle to record shortcut
    @Published var toggleShortcutKeyCode: UInt16 = 17  // T key
    @Published var toggleShortcutModifierFlags: NSEvent.ModifierFlags = [.command, .shift]

    // Audio output settings
    @Published var playbackVolume: Double = 1.0
    @Published var selectedOutputDeviceID: String?

    // App appearance
    @Published var showDockIcon: Bool = false
    @Published var showPlaybackIndicator: Bool = true
    @Published var playFeedbackSounds: Bool = false

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordedFileURL: URL?
    private var cancellables = Set<AnyCancellable>()
    private var isInitialLoad = true
    private var playbackTimer: Timer?

    init() {
        loadSettings()
        DispatchQueue.main.async { [weak self] in
            self?.isInitialLoad = false
            self?.setupAutoSave()
        }
    }

    private func setupAutoSave() {
        Publishers.CombineLatest4(
            $playbackDelay,
            $holdModeEnabled,
            $toggleModeEnabled,
            $shortcutKeyCode
        )
        .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self = self, !self.isInitialLoad else { return }
            self.saveSettings()
        }
        .store(in: &cancellables)

        Publishers.CombineLatest4(
            $shortcutModifierFlags,
            $toggleShortcutKeyCode,
            $toggleShortcutModifierFlags,
            $isRecording
        )
        .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
        .sink { [weak self] _, _, _, isRecording in
            guard let self = self, !self.isInitialLoad else { return }
            if !isRecording {
                self.saveSettings()
            }
        }
        .store(in: &cancellables)

        Publishers.CombineLatest4(
            $playbackVolume,
            $selectedOutputDeviceID,
            $showDockIcon,
            $showPlaybackIndicator
        )
        .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self = self, !self.isInitialLoad else { return }
            self.saveSettings()
        }
        .store(in: &cancellables)

        $playFeedbackSounds
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, !self.isInitialLoad else { return }
                self.saveSettings()
            }
            .store(in: &cancellables)
    }

    func loadSettings() {
        if let savedDelay = UserDefaults.standard.value(forKey: "playbackDelay") as? Double {
            playbackDelay = savedDelay
        }
        if let savedHoldEnabled = UserDefaults.standard.value(forKey: "holdModeEnabled") as? Bool {
            holdModeEnabled = savedHoldEnabled
        }
        if let savedToggleEnabled = UserDefaults.standard.value(forKey: "toggleModeEnabled") as? Bool {
            toggleModeEnabled = savedToggleEnabled
        }
        if let savedKeyCode = UserDefaults.standard.value(forKey: "shortcutKeyCode") as? UInt16 {
            shortcutKeyCode = savedKeyCode
        }
        if let savedModifiers = UserDefaults.standard.value(forKey: "shortcutModifierFlags") as? UInt {
            shortcutModifierFlags = NSEvent.ModifierFlags(rawValue: savedModifiers)
        }
        if let savedToggleKeyCode = UserDefaults.standard.value(forKey: "toggleShortcutKeyCode") as? UInt16 {
            toggleShortcutKeyCode = savedToggleKeyCode
        }
        if let savedToggleModifiers = UserDefaults.standard.value(forKey: "toggleShortcutModifierFlags") as? UInt {
            toggleShortcutModifierFlags = NSEvent.ModifierFlags(rawValue: savedToggleModifiers)
        }
        if let savedVolume = UserDefaults.standard.value(forKey: "playbackVolume") as? Double {
            playbackVolume = savedVolume
        }
        if let savedOutputDeviceID = UserDefaults.standard.string(forKey: "selectedOutputDeviceID") {
            selectedOutputDeviceID = savedOutputDeviceID
        }
        if let savedShowDockIcon = UserDefaults.standard.value(forKey: "showDockIcon") as? Bool {
            showDockIcon = savedShowDockIcon
        }
        if let savedShowPlaybackIndicator = UserDefaults.standard.value(forKey: "showPlaybackIndicator") as? Bool {
            showPlaybackIndicator = savedShowPlaybackIndicator
        }
        if let savedPlayFeedback = UserDefaults.standard.value(forKey: "playFeedbackSounds") as? Bool {
            playFeedbackSounds = savedPlayFeedback
        }
    }

    func saveSettings() {
        UserDefaults.standard.set(playbackDelay, forKey: "playbackDelay")
        UserDefaults.standard.set(holdModeEnabled, forKey: "holdModeEnabled")
        UserDefaults.standard.set(toggleModeEnabled, forKey: "toggleModeEnabled")
        UserDefaults.standard.set(shortcutKeyCode, forKey: "shortcutKeyCode")
        UserDefaults.standard.set(shortcutModifierFlags.rawValue, forKey: "shortcutModifierFlags")
        UserDefaults.standard.set(toggleShortcutKeyCode, forKey: "toggleShortcutKeyCode")
        UserDefaults.standard.set(toggleShortcutModifierFlags.rawValue, forKey: "toggleShortcutModifierFlags")
        UserDefaults.standard.set(playbackVolume, forKey: "playbackVolume")
        if let deviceID = selectedOutputDeviceID {
            UserDefaults.standard.set(deviceID, forKey: "selectedOutputDeviceID")
        } else {
            UserDefaults.standard.removeObject(forKey: "selectedOutputDeviceID")
        }
        UserDefaults.standard.set(showDockIcon, forKey: "showDockIcon")
        UserDefaults.standard.set(showPlaybackIndicator, forKey: "showPlaybackIndicator")
        UserDefaults.standard.set(playFeedbackSounds, forKey: "playFeedbackSounds")
    }

    func startRecording() {
        guard !isRecording else { return }

        let tempDir = FileManager.default.temporaryDirectory
        recordedFileURL = tempDir.appendingPathComponent("recording_\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: recordedFileURL!, settings: settings)
            audioRecorder?.record()
            isRecording = true
            print("Recording started")
            playStartSound()
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    func stopRecordingAndPlayback() {
        guard isRecording else { return }

        audioRecorder?.stop()
        isRecording = false
        print("Recording stopped")
        playStopSound()

        DispatchQueue.main.asyncAfter(deadline: .now() + playbackDelay) { [weak self] in
            self?.playRecording()
        }
    }

    func playRecording() {
        guard let url = recordedFileURL else {
            print("No recording found")
            return
        }

        do {
            if let deviceID = selectedOutputDeviceID {
                setOutputDevice(deviceID: deviceID)
            }

            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.volume = Float(playbackVolume)
            audioPlayer?.play()
            isPlaying = true
            playbackProgress = 0.0
            print("Playing recording at volume: \(playbackVolume)")

            startPlaybackTimer()

            DispatchQueue.main.asyncAfter(deadline: .now() + (audioPlayer?.duration ?? 0) + 0.1) { [weak self] in
                self?.stopPlayback()
            }
        } catch {
            print("Failed to play recording: \(error)")
        }
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.audioPlayer else { return }
            if player.duration > 0 {
                self.playbackProgress = player.currentTime / player.duration
            }
        }
    }

    private func stopPlayback() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        isPlaying = false
        playbackProgress = 0.0
        cleanupRecording()
    }

    func cleanupRecording() {
        guard let url = recordedFileURL else { return }
        try? FileManager.default.removeItem(at: url)
        recordedFileURL = nil
    }

    func getAvailableInputDevices() -> [AVCaptureDevice] {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return discoverySession.devices
    }

    // MARK: - Audio Output Device Management

    struct AudioOutputDevice: Identifiable, Hashable {
        let id: String
        let name: String
        let uid: String
    }

    func getAvailableOutputDevices() -> [AudioOutputDevice] {
        var devices: [AudioOutputDevice] = []

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == kAudioHardwareNoError else { return devices }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var audioDevices = [AudioDeviceID](repeating: 0, count: deviceCount)

        let getDevicesStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &audioDevices
        )

        guard getDevicesStatus == kAudioHardwareNoError else { return devices }

        for deviceID in audioDevices {
            var streamPropertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )

            var streamDataSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(deviceID, &streamPropertyAddress, 0, nil, &streamDataSize)

            if streamDataSize > 0 {
                if let name = getDeviceName(deviceID: deviceID),
                   let uid = getDeviceUID(deviceID: deviceID) {
                    devices.append(AudioOutputDevice(id: uid, name: name, uid: uid))
                }
            }
        }

        return devices
    }

    private func getDeviceName(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize = UInt32(MemoryLayout<CFString>.size)
        var deviceName: CFString = "" as CFString

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &deviceName)
        guard status == kAudioHardwareNoError else { return nil }

        return deviceName as String
    }

    private func getDeviceUID(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize = UInt32(MemoryLayout<CFString>.size)
        var deviceUID: CFString = "" as CFString

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &deviceUID)
        guard status == kAudioHardwareNoError else { return nil }

        return deviceUID as String
    }

    private func setOutputDevice(deviceID: String) {
        guard let audioDeviceID = getAudioDeviceID(byUID: deviceID) else {
            print("Could not find audio device with UID: \(deviceID)")
            return
        }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceIDToSet = audioDeviceID
        let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &deviceIDToSet
        )

        if status == kAudioHardwareNoError {
            print("Successfully set output device to: \(deviceID)")
        } else {
            print("Failed to set output device. Status: \(status)")
        }
    }

    private func getAudioDeviceID(byUID uid: String) -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var audioDevices = [AudioDeviceID](repeating: 0, count: deviceCount)

        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &audioDevices)

        for deviceID in audioDevices {
            if let deviceUID = getDeviceUID(deviceID: deviceID), deviceUID == uid {
                return deviceID
            }
        }

        return nil
    }

    private func playStartSound() {
        guard playFeedbackSounds else { return }
        NSSound(named: "Purr")?.play()
    }

    private func playStopSound() {
        guard playFeedbackSounds else { return }
        NSSound(named: "Bottle")?.play()
    }
}
