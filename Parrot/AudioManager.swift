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

class AudioManager: NSObject, ObservableObject, AVAudioPlayerDelegate, AVAudioRecorderDelegate {
    @Published private(set) var lastError: String?
    @Published var playbackDelay: Double = 0.5
    @Published var selectedInputDeviceUID: String?
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var isPaused = false
    @Published var hasSoundStarted = false
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
    @Published var showDockIcon: Bool = true
    @Published var showMenuBarIcon: Bool = true
    @Published var showPlaybackIndicator: Bool = true
    @Published var playFeedbackSounds: Bool = false
    @Published var overlayDismissDelay: Double = 5.0  // 1-20 seconds

    // Recording safety net: a stuck modifier key should not record forever.
    @Published var maxRecordingDuration: Double = 120.0  // 10-600 seconds
    /// Keep finished recordings on disk so they can be saved from the menu bar.
    @Published var keepRecordings: Bool = true

    /// Live microphone level, 0...1, updated while recording. Drives the waveform.
    @Published var recordingLevel: Double = 0.0
    /// Seconds elapsed in the current recording.
    @Published var recordingDuration: TimeInterval = 0

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordedFileURL: URL?
    private var cancellables = Set<AnyCancellable>()
    private var isInitialLoad = true
    private var playbackTimer: Timer?
    private var recordingTimer: Timer?

    // System defaults to put back once we are done borrowing them
    private var previousDefaultInputUID: String?
    private var appliedInputUID: String?
    private let playbackScheduler = PlaybackScheduler()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        loadSettings()
        DispatchQueue.main.async { [weak self] in
            self?.isInitialLoad = false
            self?.setupAutoSave()
        }
    }

    /// Persists settings shortly after any of them changes.
    ///
    /// This used to be four stacked `CombineLatest4`s - one of them padded with a
    /// duplicate publisher to reach arity 4, another firing on `$isRecording`.
    /// Merging the streams means adding a setting is a one-line change.
    private func setupAutoSave() {
        let settingsChanged: [AnyPublisher<Void, Never>] = [
            $playbackDelay.map { _ in }.eraseToAnyPublisher(),
            $holdModeEnabled.map { _ in }.eraseToAnyPublisher(),
            $toggleModeEnabled.map { _ in }.eraseToAnyPublisher(),
            $shortcutKeyCode.map { _ in }.eraseToAnyPublisher(),
            $shortcutModifierFlags.map { _ in }.eraseToAnyPublisher(),
            $toggleShortcutKeyCode.map { _ in }.eraseToAnyPublisher(),
            $toggleShortcutModifierFlags.map { _ in }.eraseToAnyPublisher(),
            $playbackVolume.map { _ in }.eraseToAnyPublisher(),
            $selectedInputDeviceUID.map { _ in }.eraseToAnyPublisher(),
            $selectedOutputDeviceID.map { _ in }.eraseToAnyPublisher(),
            $showDockIcon.map { _ in }.eraseToAnyPublisher(),
            $showMenuBarIcon.map { _ in }.eraseToAnyPublisher(),
            $showPlaybackIndicator.map { _ in }.eraseToAnyPublisher(),
            $playFeedbackSounds.map { _ in }.eraseToAnyPublisher(),
            $overlayDismissDelay.map { _ in }.eraseToAnyPublisher(),
            $maxRecordingDuration.map { _ in }.eraseToAnyPublisher(),
            $keepRecordings.map { _ in }.eraseToAnyPublisher(),
        ]

        Publishers.MergeMany(settingsChanged)
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                guard let self = self, !self.isInitialLoad else { return }
                self.saveSettings()
            }
            .store(in: &cancellables)
    }

    func loadSettings() {
        // Check if this is first launch (no settings saved yet)
        let isFirstLaunch = defaults.value(forKey: "hasLaunchedBefore") == nil

        if let savedDelay = defaults.value(forKey: "playbackDelay") as? Double {
            playbackDelay = savedDelay
        }
        if let savedHoldEnabled = defaults.value(forKey: "holdModeEnabled") as? Bool {
            holdModeEnabled = savedHoldEnabled
        }
        if let savedToggleEnabled = defaults.value(forKey: "toggleModeEnabled") as? Bool {
            toggleModeEnabled = savedToggleEnabled
        }
        if let savedKeyCode = defaults.value(forKey: "shortcutKeyCode") as? UInt16 {
            shortcutKeyCode = savedKeyCode
        }
        if let savedModifiers = defaults.value(forKey: "shortcutModifierFlags") as? UInt {
            shortcutModifierFlags = NSEvent.ModifierFlags(rawValue: savedModifiers)
        }
        if let savedToggleKeyCode = defaults.value(forKey: "toggleShortcutKeyCode") as? UInt16 {
            toggleShortcutKeyCode = savedToggleKeyCode
        }
        if let savedToggleModifiers = defaults.value(forKey: "toggleShortcutModifierFlags") as? UInt {
            toggleShortcutModifierFlags = NSEvent.ModifierFlags(rawValue: savedToggleModifiers)
        }
        if let savedVolume = defaults.value(forKey: "playbackVolume") as? Double {
            playbackVolume = savedVolume
        }
        if let savedOutputDeviceID = defaults.string(forKey: "selectedOutputDeviceID") {
            selectedOutputDeviceID = savedOutputDeviceID
        }
        if let savedInputDeviceUID = defaults.string(forKey: "selectedInputDeviceUID") {
            selectedInputDeviceUID = savedInputDeviceUID
        }
        if let savedShowDockIcon = defaults.value(forKey: "showDockIcon") as? Bool {
            showDockIcon = savedShowDockIcon
        }
        if let savedShowMenuBarIcon = defaults.value(forKey: "showMenuBarIcon") as? Bool {
            showMenuBarIcon = savedShowMenuBarIcon
        }
        if let savedShowPlaybackIndicator = defaults.value(forKey: "showPlaybackIndicator") as? Bool {
            showPlaybackIndicator = savedShowPlaybackIndicator
        }
        if let savedPlayFeedback = defaults.value(forKey: "playFeedbackSounds") as? Bool {
            playFeedbackSounds = savedPlayFeedback
        }
        if let savedOverlayDelay = defaults.value(forKey: "overlayDismissDelay") as? Double {
            overlayDismissDelay = savedOverlayDelay
        }
        if let savedMaxDuration = defaults.value(forKey: "maxRecordingDuration") as? Double {
            maxRecordingDuration = savedMaxDuration
        }
        if let savedKeepRecordings = defaults.value(forKey: "keepRecordings") as? Bool {
            keepRecordings = savedKeepRecordings
        }

        playbackDelay = Self.clamped(playbackDelay, to: 0...5, fallback: 0.5)
        playbackVolume = Self.clamped(playbackVolume, to: 0...1, fallback: 1)
        maxRecordingDuration = Self.clamped(maxRecordingDuration, to: 10...600, fallback: 120)
        overlayDismissDelay = Self.clamped(overlayDismissDelay, to: 1...20, fallback: 5)

        // Safety: On first launch, always show dock icon
        if isFirstLaunch {
            showDockIcon = true
            showMenuBarIcon = true
            defaults.set(true, forKey: "hasLaunchedBefore")
        }

        // Safety: Ensure at least one icon is always visible
        if !showDockIcon && !showMenuBarIcon {
            showDockIcon = true
        }
    }

    private static func clamped(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }

    func saveSettings() {
        // Safety: Ensure at least one icon is always visible before saving
        if !showDockIcon && !showMenuBarIcon {
            showDockIcon = true
        }

        defaults.set(playbackDelay, forKey: "playbackDelay")
        defaults.set(holdModeEnabled, forKey: "holdModeEnabled")
        defaults.set(toggleModeEnabled, forKey: "toggleModeEnabled")
        defaults.set(shortcutKeyCode, forKey: "shortcutKeyCode")
        defaults.set(shortcutModifierFlags.rawValue, forKey: "shortcutModifierFlags")
        defaults.set(toggleShortcutKeyCode, forKey: "toggleShortcutKeyCode")
        defaults.set(toggleShortcutModifierFlags.rawValue, forKey: "toggleShortcutModifierFlags")
        defaults.set(playbackVolume, forKey: "playbackVolume")
        defaults.setOrRemove(selectedOutputDeviceID, forKey: "selectedOutputDeviceID")
        defaults.setOrRemove(selectedInputDeviceUID, forKey: "selectedInputDeviceUID")
        defaults.set(showDockIcon, forKey: "showDockIcon")
        defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon")
        defaults.set(showPlaybackIndicator, forKey: "showPlaybackIndicator")
        defaults.set(playFeedbackSounds, forKey: "playFeedbackSounds")
        defaults.set(overlayDismissDelay, forKey: "overlayDismissDelay")
        defaults.set(maxRecordingDuration, forKey: "maxRecordingDuration")
        defaults.set(keepRecordings, forKey: "keepRecordings")
    }

    // MARK: - Recording

    func startRecording() {
        guard !isRecording else { return }

        // The previous take is finished with by the time a new one starts.
        playbackScheduler.cancel()
        lastError = nil
        discardCurrentRecording()
        applyInputDevice()

        let url = RecordingStore.newRecordingURL()

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record(forDuration: maxRecordingDuration) else {
                Log.audio.error("AVAudioRecorder refused to start")
                lastError = "Recording couldn’t start. Check microphone access and the selected input device."
                try? FileManager.default.removeItem(at: url)
                restoreDefaultDevices()
                return
            }
            recorder.delegate = self

            audioRecorder = recorder
            recordedFileURL = url
            recordingDuration = 0
            recordingLevel = 0
            isRecording = true
            startRecordingTimer()
            playStartSound()
            Log.audio.info("Recording started")
        } catch {
            lastError = "Recording failed: \(error.localizedDescription)"
            try? FileManager.default.removeItem(at: url)
            Log.audio.error("Failed to start recording: \(error.localizedDescription)")
            restoreDefaultDevices()
        }
    }

    func stopRecordingAndPlayback() {
        guard isRecording else { return }

        audioRecorder?.delegate = nil
        audioRecorder?.stop()
        audioRecorder = nil
        stopRecordingTimer()
        isRecording = false
        restoreDefaultDevices()
        playStopSound()
        Log.audio.info("Recording stopped after \(self.recordingDuration, format: .fixed(precision: 1))s")

        finishTakeAndSchedulePlayback()
    }

    /// Samples the microphone level so the indicator can show what is actually
    /// being picked up, rather than the canned sine wave it used to animate.
    private func startRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, let recorder = self.audioRecorder, recorder.isRecording else { return }
            recorder.updateMeters()
            self.recordingLevel = Self.normalizedLevel(fromDecibels: recorder.averagePower(forChannel: 0))
            self.recordingDuration = recorder.currentTime
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingLevel = 0
    }

    /// Maps AVAudioRecorder's dBFS reading (roughly -160...0) onto 0...1.
    ///
    /// The floor is -50 dB rather than -160 because normal speech sits between
    /// about -30 and -5 dB; using the full range leaves the meter barely moving.
    static func normalizedLevel(fromDecibels decibels: Float) -> Double {
        let floor: Float = -50
        guard decibels.isFinite else { return 0 }
        let clamped = max(floor, min(0, decibels))
        return Double((clamped - floor) / -floor)
    }

    // MARK: - AVAudioRecorderDelegate

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self, weak recorder] in
            guard let self, let recorder, self.audioRecorder === recorder, self.isRecording else { return }
            self.stopRecordingTimer()
            self.audioRecorder = nil
            self.isRecording = false
            self.restoreDefaultDevices()
            if flag {
                self.playStopSound()
                self.finishTakeAndSchedulePlayback()
            } else {
                self.lastError = "The recording was interrupted and couldn’t be completed."
            }
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        guard audioRecorder === recorder else { return }
        cancelRecording()
        lastError = "Recording failed: \(error?.localizedDescription ?? "Audio encoding error.")"
    }

    private func finishTakeAndSchedulePlayback() {
        pruneStoredRecordings()
        guard let url = currentRecordingURL else { return }
        playbackScheduler.schedule(after: playbackDelay) { [weak self] in
            guard let self, !self.isRecording, self.currentRecordingURL == url else { return }
            self.play(url: url)
        }
    }

    /// Sleep and termination must never start a delayed playback or leave the mic open.
    func cancelRecording() {
        playbackScheduler.cancel()
        audioRecorder?.delegate = nil
        audioRecorder?.stop()
        audioRecorder = nil
        stopRecordingTimer()
        isRecording = false
        restoreDefaultDevices()
        pruneStoredRecordings()
    }

    // MARK: - Playback

    func playRecording() {
        guard let url = recordedFileURL else {
            Log.audio.error("No recording to play")
            return
        }
        play(url: url)
    }

    /// Plays an arbitrary stored take, e.g. one picked from the menu bar.
    func play(url: URL) {
        guard !isRecording else { return }
        stopPlayback()
        lastError = nil
        recordedFileURL = url

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.volume = Float(playbackVolume)
            if let uid = selectedOutputDeviceID { player.currentDevice = uid }
            guard player.prepareToPlay(), player.play() else {
                lastError = "Playback couldn’t start. Check the selected output device."
                return
            }

            audioPlayer = player
            isPlaying = true
            isPaused = false
            hasSoundStarted = false
            playbackProgress = 0.0
            startPlaybackTimer()
        } catch {
            lastError = "Playback failed: \(error.localizedDescription)"
            Log.audio.error("Failed to play recording: \(error.localizedDescription)")
            restoreDefaultDevices()
        }
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.audioPlayer else { return }

            // Only update progress when actually playing (not when paused)
            if player.isPlaying {
                if player.duration > 0 {
                    self.playbackProgress = player.currentTime / player.duration
                }
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self, weak player] in
            guard let self, let player, self.audioPlayer === player else { return }
            self.onPlaybackFinished()
            if !flag { self.lastError = "Playback ended unexpectedly." }
        }
    }

    private func onPlaybackFinished() {
        stopPlaybackTimer()
        isPlaying = false
        isPaused = false
        playbackProgress = 1.0
        restoreDefaultDevices()
        // The file stays put so the overlay can replay it, and so it can be saved.
    }

    func togglePlayback() {
        guard let player = audioPlayer else { return }
        if player.isPlaying {
            player.pause()
            isPaused = true
            stopPlaybackTimer()  // Stop timer when paused to save energy
        } else {
            guard player.play() else { lastError = "Playback couldn’t resume."; return }
            isPlaying = true
            isPaused = false
            startPlaybackTimer()  // Resume timer when playing
        }
    }

    func seek(to progress: Double) {
        guard let player = audioPlayer else { return }
        let newTime = player.duration * progress
        player.currentTime = newTime
        playbackProgress = progress

        // If user interacts, show the UI immediately
        if !hasSoundStarted {
            hasSoundStarted = true
        }
    }

    func replayRecording() {
        guard let player = audioPlayer else { return }
        player.currentTime = 0
        player.play()
        isPlaying = true
        isPaused = false
        playbackProgress = 0.0
        startPlaybackTimer()
    }

    func stopPlayback() {
        playbackScheduler.cancel()
        stopPlaybackTimer()
        isPlaying = false
        isPaused = false
        hasSoundStarted = false
        playbackProgress = 0.0
        audioPlayer?.stop()
        audioPlayer = nil
        restoreDefaultDevices()
    }

    // MARK: - Recording files

    /// URL of the take currently loaded, if there is one on disk.
    var currentRecordingURL: URL? {
        guard let url = recordedFileURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Releases the current take, deleting the file unless the user asked to keep
    /// recordings around. Nothing used to call this, so every recording ever made
    /// stayed in the temp directory forever.
    func discardCurrentRecording() {
        stopPlayback()

        guard let url = recordedFileURL else { return }
        recordedFileURL = nil
        if !keepRecordings {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Deletes anything left behind by a previous run, and trims the kept
    /// recordings back to the retention limit.
    func pruneStoredRecordings() {
        RecordingStore.prune(keeping: keepRecordings ? RecordingStore.retentionLimit : 0,
                            excluding: recordedFileURL)
    }

    func recentRecordings() -> [Recording] {
        RecordingStore.recentRecordings()
    }

    func getAvailableInputDevices() -> [AudioDevice] {
        AudioDevices.devices(for: .input)
    }

    func getAvailableOutputDevices() -> [AudioDevice] {
        AudioDevices.devices(for: .output)
    }

    // MARK: - Device routing

    /// Recording follows the system input; playback uses AVAudioPlayer's own device.
    private func applyInputDevice() {
        guard let uid = selectedInputDeviceUID else { return }
        let previous = AudioDevices.defaultDeviceUID(for: .input)
        guard previous != uid else { return }
        if AudioDevices.setDefaultDevice(uid: uid, for: .input) {
            previousDefaultInputUID = previous
            appliedInputUID = uid
        }
    }

    /// Respect a device change the user made while Parrot was recording.
    func restoreDefaultDevices() {
        defer { previousDefaultInputUID = nil; appliedInputUID = nil }
        guard let previous = previousDefaultInputUID,
              AudioDevices.defaultDeviceUID(for: .input) == appliedInputUID else { return }
        AudioDevices.setDefaultDevice(uid: previous, for: .input)
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
