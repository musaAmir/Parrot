import XCTest
import CoreGraphics
import AVFoundation
@testable import ParrotCore

@MainActor final class RegressionTests: XCTestCase {
    func testStartCueCannotBeCapturedByMicrophone() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let name = "ParrotTests-\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "playFeedbackSounds")
        let recorder = TestRecordingSession(), feedback = TestRecordingFeedback()
        var soundWasCaptured = false
        feedback.onPlay = { soundWasCaptured = recorder.isRecording }
        let manager = AudioManager(defaults: defaults, recordingDirectory: folder, feedbackSounds: feedback) { _, _ in recorder }
        manager.startRecording()
        XCTAssertFalse(soundWasCaptured, "The microphone is already recording when the speaker cue plays")
        XCTAssertFalse(recorder.isRecording, "Capture must wait until the cue and echo gap finish")
        manager.cancelRecording()
    }

    func testStoppingOldPlaybackDoesNotInterruptNewRecordingCue() async throws {
        let (manager, recorder, feedback) = try cueFixture()
        defer { manager.cancelRecording() }
        let started = expectation(description: "New recording survives old player dismissal")
        recorder.onRecord = { started.fulfill() }
        manager.startRecording()
        manager.stopPlayback()
        XCTAssertNotNil(feedback.completion)
        feedback.finish()
        await fulfillment(of: [started], timeout: 1)
        XCTAssertTrue(recorder.isRecording)
    }

    func testCaptureWaitsForCueCompletionAndEchoGap() async throws {
        let (manager, recorder, feedback) = try cueFixture()
        defer { manager.cancelRecording() }
        let started = expectation(description: "Microphone starts after cue")
        recorder.onRecord = { started.fulfill() }
        manager.startRecording()
        XCTAssertTrue(manager.isPreparingToRecord)
        XCTAssertFalse(recorder.isRecording)
        feedback.finish()
        XCTAssertFalse(recorder.isRecording, "Keep a settling gap after sound completion")
        await fulfillment(of: [started], timeout: 1)
        XCTAssertFalse(manager.isPreparingToRecord)
        XCTAssertTrue(recorder.isRecording)
    }

    func testReleaseDuringCueTailCancelsPendingCapture() async throws {
        let (manager, recorder, feedback) = try cueFixture()
        defer { manager.cancelRecording() }
        let unwanted = expectation(description: "Cancelled take must not start")
        unwanted.isInverted = true
        recorder.onRecord = { unwanted.fulfill() }
        manager.startRecording(); feedback.finish()
        manager.stopRecordingAndPlayback()
        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(manager.isPreparingToRecord)
        await fulfillment(of: [unwanted], timeout: 0.08)
        XCTAssertTrue(recorder.limits.isEmpty)
    }

    func testOldCueCallbackCannotStartANewTakeEarly() async throws {
        let (manager, recorder, feedback) = try cueFixture()
        defer { manager.cancelRecording() }
        manager.startRecording()
        let staleCompletion = feedback.completion
        manager.stopRecordingAndPlayback()
        manager.startRecording()
        staleCompletion?()
        let early = expectation(description: "Old cue must not start the next take")
        early.isInverted = true
        recorder.onRecord = { early.fulfill() }
        await fulfillment(of: [early], timeout: 0.08)
        XCTAssertTrue(manager.isPreparingToRecord)
        let started = expectation(description: "New cue allows capture")
        recorder.onRecord = { started.fulfill() }
        feedback.finish()
        await fulfillment(of: [started], timeout: 1)
        XCTAssertEqual(recorder.limits.count, 1)
    }

    func testStopCueWaitsForClosedMicrophoneAndDelaysPlayback() async throws {
        let (manager, recorder, feedback) = try cueFixture()
        defer { manager.cancelRecording() }
        manager.playbackDelay = 0
        let started = expectation(description: "Capture starts")
        recorder.onRecord = { started.fulfill() }
        manager.startRecording(); feedback.finish()
        await fulfillment(of: [started], timeout: 1)
        let url = manager.currentRecordingURL
        var cueCaptured = false
        feedback.onPlay = { cueCaptured = recorder.isRecording }
        let early = expectation(description: "Playback must wait for stop cue")
        early.isInverted = true
        manager.onPlayback = { early.fulfill() }
        manager.stopRecordingAndPlayback()
        XCTAssertFalse(cueCaptured)
        XCTAssertEqual(feedback.cues.last, .stop)
        await fulfillment(of: [early], timeout: 0.05)
        let played = expectation(description: "Playback after stop cue")
        manager.onPlayback = { played.fulfill() }
        feedback.finish()
        await fulfillment(of: [played], timeout: 1)
        XCTAssertEqual(manager.playedURLs, [url!])
    }

    private func cueFixture() throws -> (PlaybackObservationManager, TestRecordingSession, TestRecordingFeedback) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "ParrotTests-\(UUID())", defaults = UserDefaults(suiteName: name)!
        defaults.set(true, forKey: "playFeedbackSounds")
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: folder)
        }
        let recorder = TestRecordingSession(), feedback = TestRecordingFeedback()
        let manager = PlaybackObservationManager(defaults: defaults, recordingDirectory: folder, feedbackSounds: feedback, feedbackSettlingDelay: 0.03) { url, _ in
            try Data().write(to: url)
            return recorder
        }
        return (manager, recorder, feedback)
    }

    func testRecordingPauseResumesSameTakeWithRemainingLimitAndStops() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let name = "ParrotTests-\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let recorder = TestRecordingSession()
        var creations = 0
        let manager = AudioManager(defaults: defaults, recordingDirectory: folder) { url, _ in
            creations += 1
            try Data().write(to: url)
            return recorder
        }
        manager.startRecording()
        let originalURL = manager.currentRecordingURL
        XCTAssertTrue(manager.isRecording)
        recorder.currentTime = 30
        manager.toggleRecordingPause()
        XCTAssertTrue(manager.isRecording)
        XCTAssertTrue(manager.isRecordingPaused)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(manager.recordingDuration, 30)
        manager.toggleRecordingPause()
        XCTAssertFalse(manager.isRecordingPaused)
        XCTAssertTrue(recorder.isRecording)
        XCTAssertEqual(recorder.limits, [120, 90])
        XCTAssertEqual(creations, 1)
        XCTAssertEqual(manager.currentRecordingURL, originalURL)
        manager.toggleRecordingPause()
        manager.stopRecordingAndPlayback()
        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(manager.isRecordingPaused)
        XCTAssertEqual(recorder.stops, 1)
        manager.stopPlayback() // Cancel scheduled playback of this disposable fake file.
    }

    func testFailedResumeStaysPausedAndCancelClearsPauseState() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let name = "ParrotTests-\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let recorder = TestRecordingSession()
        let manager = AudioManager(defaults: defaults, recordingDirectory: folder) { _, _ in recorder }
        manager.startRecording(); manager.toggleRecordingPause()
        recorder.succeeds = false
        manager.toggleRecordingPause()
        XCTAssertTrue(manager.isRecordingPaused)
        XCTAssertTrue(manager.isRecording)
        XCTAssertNotNil(manager.lastError)
        manager.cancelRecording()
        XCTAssertFalse(manager.isRecordingPaused)
        XCTAssertFalse(manager.isRecording)
    }

    func testKeyReleaseAfterModifiersStillEndsRecording() {
        var tracker = ShortcutPressTracker()
        let hold = KeyBinding(keyCode: 6, flags: [.maskCommand, .maskShift], isEnabled: true)
        XCTAssertEqual(tracker.handle(keyCode: 6, flags: hold.flags, isDown: true, isRepeat: false, hold: hold, toggle: .disabled), .holdDown)
        XCTAssertEqual(tracker.handle(keyCode: 6, flags: [], isDown: false, isRepeat: false, hold: hold, toggle: .disabled), .holdUp)
        XCTAssertNil(tracker.handle(keyCode: 6, flags: [], isDown: false, isRepeat: false, hold: hold, toggle: .disabled))
    }

    func testShortcutRepeatIsConsumedAndUnrelatedKeysPassThrough() {
        var tracker = ShortcutPressTracker()
        let binding = KeyBinding(keyCode: 17, flags: .maskCommand, isEnabled: true)
        XCTAssertEqual(tracker.handle(keyCode: 17, flags: .maskCommand, isDown: true, isRepeat: false, hold: .disabled, toggle: binding), .toggleDown)
        XCTAssertEqual(tracker.handle(keyCode: 17, flags: .maskCommand, isDown: true, isRepeat: true, hold: .disabled, toggle: binding), .consume)
        XCTAssertNil(tracker.handle(keyCode: 19, flags: [], isDown: true, isRepeat: false, hold: .disabled, toggle: binding))
        XCTAssertEqual(tracker.handle(keyCode: 17, flags: [], isDown: false, isRepeat: false, hold: .disabled, toggle: .disabled), .toggleUp)
    }

    func testShortcutResetReleasesTracking() {
        var tracker = ShortcutPressTracker()
        let hold = KeyBinding(keyCode: 6, flags: .maskCommand, isEnabled: true)
        _ = tracker.handle(keyCode: 6, flags: hold.flags, isDown: true, isRepeat: false, hold: hold, toggle: .disabled)
        tracker.reset()
        XCTAssertNil(tracker.handle(keyCode: 6, flags: [], isDown: false, isRepeat: false, hold: hold, toggle: .disabled))
    }

    @MainActor func testCancelledDelayedPlaybackNeverStarts() async {
        let scheduler = PlaybackScheduler()
        let unexpected = expectation(description: "Cancelled playback")
        unexpected.isInverted = true
        scheduler.schedule(after: 0.01) { unexpected.fulfill() }
        scheduler.cancel()
        await fulfillment(of: [unexpected], timeout: 0.08)
    }

    @MainActor func testNewTakeSupersedesDelayedPlayback() async {
        let scheduler = PlaybackScheduler()
        var played: [String] = []
        let finished = expectation(description: "Latest take played")
        scheduler.schedule(after: 0.01) { played.append("old") }
        scheduler.schedule(after: 0.02) { played.append("new"); finished.fulfill() }
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(played, ["new"])
    }

    func testRapidTakesHaveUniqueFileNames() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let urls = (0..<100).map { _ in RecordingStore.newRecordingURL(in: folder) }
        XCTAssertEqual(Set(urls).count, 100)
        XCTAssertTrue(urls.allSatisfy { $0.deletingLastPathComponent().path == folder.path && $0.pathExtension == "m4a" })
    }

    func testRetentionPreservesActiveTakeAndUnrelatedFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let active = RecordingStore.newRecordingURL(in: folder)
        try Data().write(to: active)
        let stale = RecordingStore.newRecordingURL(in: folder)
        try Data().write(to: stale)
        let unrelated = folder.appendingPathComponent("export.m4a")
        try Data().write(to: unrelated)
        RecordingStore.prune(keeping: 0, excluding: active, in: folder)
        XCTAssertTrue(FileManager.default.fileExists(atPath: active.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testRetentionLimitIncludesTheProtectedTake() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let takes = (0..<15).map { _ in RecordingStore.newRecordingURL(in: folder) }
        for take in takes { try Data().write(to: take) }
        RecordingStore.prune(keeping: 10, excluding: takes[0], in: folder)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 10)
        XCTAssertTrue(FileManager.default.fileExists(atPath: takes[0].path))
    }

    func testCorruptPreferencesCannotCreateUnboundedRecordingOrInvalidSlider() {
        let name = "ParrotTests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(-100, forKey: "maxRecordingDuration")
        defaults.set(Double.infinity, forKey: "playbackDelay")
        defaults.set(5, forKey: "playbackVolume")
        defaults.set(-1, forKey: "overlayDismissDelay")
        let manager = AudioManager(defaults: defaults)
        XCTAssertEqual(manager.maxRecordingDuration, 10)
        XCTAssertEqual(manager.playbackDelay, 0.5)
        XCTAssertEqual(manager.playbackVolume, 1)
        XCTAssertEqual(manager.overlayDismissDelay, 1)
    }

    func testFailedPlaybackLeavesAppStoppedAndExplainsFailure() {
        let name = "ParrotTests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let manager = AudioManager(defaults: defaults)
        manager.play(url: URL(fileURLWithPath: "/nonexistent/ParrotTests-\(UUID()).m4a"))
        XCTAssertFalse(manager.isPlaying)
        XCTAssertNotNil(manager.lastError)
    }

    func testMeterHandlesSilenceAndNonFiniteValues() {
        XCTAssertEqual(AudioManager.normalizedLevel(fromDecibels: -.infinity), 0)
        XCTAssertEqual(AudioManager.normalizedLevel(fromDecibels: -160), 0)
        XCTAssertEqual(AudioManager.normalizedLevel(fromDecibels: -25), 0.5)
        XCTAssertEqual(AudioManager.normalizedLevel(fromDecibels: 10), 1)
    }

    func testUpdaterRejectsInsecureFeedAndInvalidKey() {
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        XCTAssertNoThrow(try UpdateConfiguration.validate(["SUFeedURL": "https://github.com/musaAmir/Parrot/releases/latest/download/appcast.xml", "SUPublicEDKey": key]))
        XCTAssertThrowsError(try UpdateConfiguration.validate(["SUFeedURL": "http://example.com/feed", "SUPublicEDKey": key]))
        XCTAssertThrowsError(try UpdateConfiguration.validate(["SUFeedURL": "https://example.com/feed", "SUPublicEDKey": "invalid"]))
    }
}

private final class TestRecordingSession: RecordingSession {
    weak var delegate: AVAudioRecorderDelegate?
    var isMeteringEnabled = false
    var isRecording = false
    var currentTime: TimeInterval = 0
    var limits: [TimeInterval] = []
    var stops = 0
    var succeeds = true
    var onRecord: (() -> Void)?
    func record(forDuration duration: TimeInterval) -> Bool {
        limits.append(duration); isRecording = succeeds; onRecord?(); return succeeds
    }
    func pause() { isRecording = false }
    func stop() { stops += 1; isRecording = false }
    func updateMeters() {}
    func averagePower(forChannel channelNumber: Int) -> Float { -50 }
}

private final class TestRecordingFeedback: RecordingFeedback {
    var completion: (() -> Void)?
    var cues: [RecordingCue] = []
    var onPlay: (() -> Void)?
    func play(_ cue: RecordingCue, completion: @escaping () -> Void) {
        cues.append(cue); self.completion = completion; onPlay?()
    }
    func cancel() { completion = nil }
    func finish() { let action = completion; completion = nil; action?() }
}

private final class PlaybackObservationManager: AudioManager {
    var onPlayback: (() -> Void)?
    var playedURLs: [URL] = []
    override func play(url: URL) { playedURLs.append(url); onPlayback?() }
}
