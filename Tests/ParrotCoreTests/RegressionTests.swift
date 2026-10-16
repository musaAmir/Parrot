import XCTest
import CoreGraphics
@testable import ParrotCore

@MainActor final class RegressionTests: XCTestCase {
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
