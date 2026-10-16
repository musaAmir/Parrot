// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ParrotCore",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ParrotCore", path: "Parrot", exclude: [
            "Assets.xcassets", "Info.plist", "Parrot.entitlements", "ParrotApp.swift",
            "AppDelegate.swift", "PermissionManager.swift", "SettingsView.swift",
            "ShortcutRecorder.swift", "KeyCodeFormatter.swift", "RecordingIndicatorWindow.swift",
            "PlaybackIndicatorWindow.swift", "UpdateController.swift"
        ], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "ParrotCoreTests", dependencies: ["ParrotCore"], swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
