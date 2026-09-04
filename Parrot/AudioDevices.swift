//
//  AudioDevices.swift
//  Parrot
//
//  CoreAudio device enumeration and default-device selection.
//

import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Hashable {
    let uid: String
    let name: String

    var id: String { uid }
}

enum AudioDeviceDirection {
    case input
    case output

    var scope: AudioObjectPropertyScope {
        switch self {
        case .input: return kAudioDevicePropertyScopeInput
        case .output: return kAudioDevicePropertyScopeOutput
        }
    }

    var defaultDeviceSelector: AudioObjectPropertySelector {
        switch self {
        case .input: return kAudioHardwarePropertyDefaultInputDevice
        case .output: return kAudioHardwarePropertyDefaultOutputDevice
        }
    }
}

enum AudioDevices {

    // MARK: - Enumeration

    static func devices(for direction: AudioDeviceDirection) -> [AudioDevice] {
        allDeviceIDs().compactMap { deviceID in
            guard hasStreams(deviceID: deviceID, direction: direction),
                  let name = name(of: deviceID),
                  let uid = uid(of: deviceID)
            else { return nil }
            return AudioDevice(uid: uid, name: name)
        }
    }

    // MARK: - Default device

    static func defaultDeviceUID(for direction: AudioDeviceDirection) -> String? {
        var address = systemAddress(direction.defaultDeviceSelector)
        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID
        )
        guard status == kAudioHardwareNoError else { return nil }
        return uid(of: deviceID)
    }

    /// Points the system default device at `uid`.
    ///
    /// CoreAudio has no per-player device selection for `AVAudioPlayer`, so this
    /// is how Parrot honours a device choice. Callers are responsible for putting
    /// the previous default back - see `AudioManager.restoreDefaultDevices()`.
    @discardableResult
    static func setDefaultDevice(uid: String, for direction: AudioDeviceDirection) -> Bool {
        guard let deviceID = deviceID(forUID: uid) else {
            Log.audio.error("No audio device with UID \(uid, privacy: .public)")
            return false
        }

        var address = systemAddress(direction.defaultDeviceSelector)
        var target = deviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &target
        )

        if status != kAudioHardwareNoError {
            Log.audio.error("Failed to set default device (status \(status))")
            return false
        }
        return true
    }

    // MARK: - Internals

    private static func systemAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = systemAddress(kAudioHardwarePropertyDevices)

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        ) == kAudioHardwareNoError else { return [] }

        var deviceIDs = [AudioDeviceID](repeating: 0, count: Int(dataSize) / MemoryLayout<AudioDeviceID>.size)
        guard !deviceIDs.isEmpty else { return [] }

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs
        ) == kAudioHardwareNoError else { return [] }

        return deviceIDs
    }

    private static func hasStreams(deviceID: AudioDeviceID, direction: AudioDeviceDirection) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: direction.scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        return dataSize > 0
    }

    private static func deviceID(forUID uid: String) -> AudioDeviceID? {
        allDeviceIDs().first { self.uid(of: $0) == uid }
    }

    private static func name(of deviceID: AudioDeviceID) -> String? {
        stringProperty(kAudioDevicePropertyDeviceNameCFString, of: deviceID)
    }

    private static func uid(of deviceID: AudioDeviceID) -> String? {
        stringProperty(kAudioDevicePropertyDeviceUID, of: deviceID)
    }

    /// Reads a CFString-valued property.
    ///
    /// CoreAudio hands back a +1 CFString here, so it has to be received through
    /// an `Unmanaged` box. Passing `&someCFStringVar` compiles but is wrong - it
    /// forms a raw pointer to a variable holding an object reference, and leaks.
    private static func stringProperty(
        _ selector: AudioObjectPropertySelector, of deviceID: AudioDeviceID
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, pointer)
        }

        guard status == kAudioHardwareNoError, let value = value else { return nil }
        return value.takeRetainedValue() as String
    }
}
