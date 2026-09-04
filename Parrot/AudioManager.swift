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
    private var previousDefaultOutputUID: String?

    override init() {
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
        let isFirstLaunch = UserDefaults.standard.value(forKey: "hasLaunchedBefore") == nil

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
        if let savedInputDeviceUID = UserDefaults.standard.string(forKey: "selectedInputDeviceUID") {
            selectedInputDeviceUID = savedInputDeviceUID
        }
        if let savedShowDockIcon = UserDefaults.standard.value(forKey: "showDockIcon") as? Bool {
            showDockIcon = savedShowDockIcon
        }
        if let savedShowMenuBarIcon = UserDefaults.standard.value(forKey: "showMenuBarIcon") as? Bool {
            showMenuBarIcon = savedShowMenuBarIcon
        }
        if let savedShowPlaybackIndicator = UserDefaults.standard.value(forKey: "showPlaybackIndicator") as? Bool {
            showPlaybackIndicator = savedShowPlaybackIndicator
        }
        if let savedPlayFeedback = UserDefaults.standard.value(forKey: "playFeedbackSounds") as? Bool {
            playFeedbackSounds = savedPlayFeedback
        }
        if let savedOverlayDelay = UserDefaults.standard.value(forKey: "overlayDismissDelay") as? Double {
            overlayDismissDelay = savedOverlayDelay
        }
        if let savedMaxDuration = UserDefaults.standard.value(forKey: "maxRecordingDuration") as? Double {
            maxRecordingDuration = savedMaxDuration
        }
        if let savedKeepRecordings = UserDefaults.standard.value(forKey: "keepRecordings") as? Bool {
            keepRecordings = savedKeepRecordings
        }

        // Safety: On first launch, always show dock icon
        if isFirstLaunch {
            showDockIcon = true
            showMenuBarIcon = true
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        }

        // Safety: Ensure at least one icon is always visible
        if !showDockIcon && !showMenuBarIcon {
            showDockIcon = true
        }
    }

    func saveSettings() {
        // Safety: Ensure at least one icon is always visible before saving
        if !showDockIcon && !showMenuBarIcon {
            showDockIcon = true
        }

        UserDefaults.standard.set(playbackDelay, forKey: "playbackDelay")
        UserDefaults.standard.set(holdModeEnabled, forKey: "holdModeEnabled")
        UserDefaults.standard.set(toggleModeEnabled, forKey: "toggleModeEnabled")
        UserDefaults.standard.set(shortcutKeyCode, forKey: "shortcutKeyCode")
        UserDefaults.standard.set(shortcutModifierFlags.rawValue, forKey: "shortcutModifierFlags")
        UserDefaults.standard.set(toggleShortcutKeyCode, forKey: "toggleShortcutKeyCode")
        UserDefaults.standard.set(toggleShortcutModifierFlags.rawValue, forKey: "toggleShortcutModifierFlags")
        UserDefaults.standard.set(playbackVolume, forKey: "playbackVolume")
        UserDefaults.standard.setOrRemove(selectedOutputDeviceID, forKey: "selectedOutputDeviceID")
        UserDefaults.standard.setOrRemove(selectedInputDeviceUID, forKey: "selectedInputDeviceUID")
        UserDefaults.standard.set(showDockIcon, forKey: "showDockIcon")
        UserDefaults.standard.set(showMenuBarIcon, forKey: "showMenuBarIcon")
        UserDefaults.standard.set(showPlaybackIndicator, forKey: "showPlaybackIndicator")
        UserDefaults.standard.set(playFeedbackSounds, forKey: "playFeedbackSounds")
        UserDefaults.standard.set(overlayDismissDelay, forKey: "overlayDismissDelay")
        UserDefaults.standard.set(maxRecordingDuration, forKey: "maxRecordingDuration")
        UserDefaults.standard.set(keepRecordings, forKey: "keepRecordings")
    }

    // MARK: - Recording

    func startRecording() {
        guard !isRecording else { return }

        // The previous take is finished with by the time a new one starts.
        discardCurrentRecording()
        applyDefaultDevices(input: true, output: false)

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
            Log.audio.error("Failed to start recording: \(error.localizedDescription)")
            restoreDefaultDevices()
        }
    }

    func stopRecordingAndPlayback() {
        guard isRecording else { return }

        audioRecorder?.stop()
        stopRecordingTimer()
        isRecording = false
        restoreDefaultDevices()
        playStopSound()
        Log.audio.info("Recording stopped after \(self.recordingDuration, format: .fixed(precision: 1))s")

        DispatchQueue.main.asyncAfter(deadline: .now() + playbackDelay) { [weak self] in
            self?.playRecording()
        }
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isRecording else { return }
            // Only reached when `record(forDuration:)` hit the cap.
            Log.audio.notice("Recording hit the maximum duration and stopped automatically")
            self.stopRecordingTimer()
            self.isRecording = false
            self.restoreDefaultDevices()
            self.playStopSound()
            DispatchQueue.main.asyncAfter(deadline: .now() + self.playbackDelay) { [weak self] in
                self?.playRecording()
            }
        }
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
        recordedFileURL = url

        applyDefaultDevices(input: false, output: true)

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.volume = Float(playbackVolume)
            player.prepareToPlay()
            player.play()

            audioPlayer = player
            isPlaying = true
            isPaused = false
            hasSoundStarted = false
            playbackProgress = 0.0
            startPlaybackTimer()
        } catch {
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
        DispatchQueue.main.async { [weak self] in
            self?.onPlaybackFinished()
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
            player.play()
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
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        isPaused = false
        playbackProgress = 0

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

    /// Applies the user's device choices by moving the system defaults, having
    /// first recorded what they were.
    ///
    /// AVAudioRecorder and AVAudioPlayer both follow the system default and give
    /// us no way to target a device directly, so this is the only lever available.
    /// Every caller must pair it with `restoreDefaultDevices()`; previously the
    /// output device was changed and never put back, which left the user's whole
    /// machine routed to whatever Parrot last used.
    private func applyDefaultDevices(input: Bool, output: Bool) {
        if input, let uid = selectedInputDeviceUID {
            previousDefaultInputUID = AudioDevices.defaultDeviceUID(for: .input)
            if !AudioDevices.setDefaultDevice(uid: uid, for: .input) {
                previousDefaultInputUID = nil
            }
        }
        if output, let uid = selectedOutputDeviceID {
            previousDefaultOutputUID = AudioDevices.defaultDeviceUID(for: .output)
            if !AudioDevices.setDefaultDevice(uid: uid, for: .output) {
                previousDefaultOutputUID = nil
            }
        }
    }

    /// Puts the system defaults back the way we found them.
    func restoreDefaultDevices() {
        if let uid = previousDefaultInputUID {
            AudioDevices.setDefaultDevice(uid: uid, for: .input)
            previousDefaultInputUID = nil
        }
        if let uid = previousDefaultOutputUID {
            AudioDevices.setDefaultDevice(uid: uid, for: .output)
            previousDefaultOutputUID = nil
        }
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
