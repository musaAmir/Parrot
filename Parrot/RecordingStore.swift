//
//  RecordingStore.swift
//  Parrot
//
//  Where takes live on disk, and how old ones get cleaned up.
//

import AVFoundation
import Foundation

struct Recording: Identifiable, Hashable {
    let url: URL
    let createdAt: Date
    let duration: TimeInterval

    var id: URL { url }

    var displayName: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

enum RecordingStore {
    /// How many finished takes to keep when the user has recordings turned on.
    static let retentionLimit = 10

    private static let fileExtension = "m4a"
    private static let filePrefix = "recording_"

    /// Application Support rather than the temp directory: takes now outlive the
    /// session so they can be saved from the menu bar, and the app is responsible
    /// for pruning them itself.
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base
            .appendingPathComponent("Parrot", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func newRecordingURL() -> URL {
        let stamp = ISO8601DateFormatter.filenameFormatter.string(from: Date())
        return directory.appendingPathComponent("\(filePrefix)\(stamp).\(fileExtension)")
    }

    static func recentRecordings() -> [Recording] {
        storedFiles()
            .prefix(retentionLimit)
            .map { url, created in
                Recording(url: url, createdAt: created, duration: duration(of: url))
            }
    }

    /// Keeps the `keeping` most recent files and deletes the rest.
    ///
    /// Also sweeps up the temp-directory files left by versions of Parrot that
    /// recorded into `NSTemporaryDirectory()` and never deleted anything.
    static func prune(keeping limit: Int, excluding inUse: URL?) {
        let files = storedFiles().map(\.url)
        for url in files.dropFirst(limit) where url != inUse {
            try? FileManager.default.removeItem(at: url)
        }
        removeLegacyTemporaryRecordings()
    }

    private static func storedFiles() -> [(url: URL, created: Date)] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return contents
            .filter { $0.pathExtension == fileExtension }
            .map { url in
                let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return (url, created)
            }
            .sorted { $0.created > $1.created }
    }

    private static func removeLegacyTemporaryRecordings() {
        let tempDirectory = FileManager.default.temporaryDirectory
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: tempDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []

        for url in contents where url.lastPathComponent.hasPrefix(filePrefix)
            && url.pathExtension == fileExtension {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func duration(of url: URL) -> TimeInterval {
        // AVAudioPlayer reads only the file header here, so this stays cheap
        // enough to call while building the menu.
        (try? AVAudioPlayer(contentsOf: url))?.duration ?? 0
    }
}

extension ISO8601DateFormatter {
    static let filenameFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        return formatter
    }()
}

extension UserDefaults {
    /// Writes `value`, or clears the key when it is nil.
    func setOrRemove(_ value: String?, forKey key: String) {
        if let value = value {
            set(value, forKey: key)
        } else {
            removeObject(forKey: key)
        }
    }
}
