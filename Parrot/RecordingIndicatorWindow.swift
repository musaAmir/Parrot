//
//  RecordingIndicatorWindow.swift
//  Parrot
//
//  Floating window that displays recording indicator with animated waveform
//

import Cocoa
import SwiftUI

class RecordingIndicatorWindow: NSWindow {
    private var initialLocation: NSPoint = .zero
    weak var appDelegate: AppDelegate?

    init(audioManager: AudioManager, appDelegate: AppDelegate? = nil) {
        self.appDelegate = appDelegate
        let screenFrame = NSScreen.main?.frame ?? NSRect.zero
        let windowWidth: CGFloat = 220
        let windowHeight: CGFloat = 50

        let savedOrigin = RecordingIndicatorWindow.loadSavedPosition(screenFrame: screenFrame, windowWidth: windowWidth, windowHeight: windowHeight)

        let contentRect = NSRect(
            x: savedOrigin.x,
            y: savedOrigin.y,
            width: windowWidth,
            height: windowHeight
        )

        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let hostingView = NSHostingView(rootView: RecordingIndicatorView(audioManager: audioManager))
        self.contentView = hostingView

        self.orderOut(nil)
    }

    private static func loadSavedPosition(screenFrame: NSRect, windowWidth: CGFloat, windowHeight: CGFloat) -> NSPoint {
        if let savedX = UserDefaults.standard.value(forKey: "recordingIndicatorX") as? CGFloat,
           let savedY = UserDefaults.standard.value(forKey: "recordingIndicatorY") as? CGFloat {
            return NSPoint(x: savedX, y: savedY)
        } else {
            let xPos = (screenFrame.width - windowWidth) / 2
            let yPos = screenFrame.height * 0.85
            return NSPoint(x: xPos, y: yPos)
        }
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        savePosition()
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Parrot", action: #selector(quitFromMenu), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self.contentView!)
    }

    @objc private func openSettingsFromMenu() {
        appDelegate?.openSettings()
    }

    @objc private func quitFromMenu() {
        NSApplication.shared.terminate(nil)
    }

    private func savePosition() {
        let origin = self.frame.origin
        UserDefaults.standard.set(origin.x, forKey: "recordingIndicatorX")
        UserDefaults.standard.set(origin.y, forKey: "recordingIndicatorY")
    }

    func show() {
        self.alphaValue = 0
        self.orderFront(nil)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.animator().alphaValue = 1.0
        })
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }
}

/// Recording indicator showing the live microphone level and elapsed time.
///
/// The bars used to be a `sin()` curve on a timer, so they looked identical
/// whether you were talking or the mic was muted. They now scroll a short
/// history of real level readings from `AVAudioRecorder`'s meters.
struct RecordingIndicatorView: View {
    @ObservedObject var audioManager: AudioManager
    @State private var levels: [Double] = Array(repeating: 0, count: barCount)
    @State private var isPulsing: Bool = false

    private static let barCount = 14
    private static let barHeight: CGFloat = 22

    /// Warn once the recording is within this many seconds of the auto-stop cap.
    private static let warningWindow: TimeInterval = 10

    private var remaining: TimeInterval {
        max(0, audioManager.maxRecordingDuration - audioManager.recordingDuration)
    }

    private var isRunningOut: Bool {
        remaining <= Self.warningWindow
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.red.opacity(isPulsing ? 1.0 : 0.45))

            HStack(spacing: 3) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(.white.opacity(0.85))
                        .frame(width: 3, height: 3 + level * (Self.barHeight - 3))
                        .frame(height: Self.barHeight)
                }
            }
            .animation(.linear(duration: 0.05), value: levels)

            Text(timeLabel)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isRunningOut ? .orange : .white.opacity(0.9))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .onReceive(audioManager.$recordingLevel) { level in
            levels.removeFirst()
            levels.append(level)
        }
        .onChange(of: audioManager.isRecording) { _, isRecording in
            if !isRecording {
                levels = Array(repeating: 0, count: Self.barCount)
            }
        }
    }

    /// Counts elapsed time normally, and switches to a countdown once the
    /// auto-stop is close, so a long take does not end without warning.
    private var timeLabel: String {
        let seconds = isRunningOut ? remaining : audioManager.recordingDuration
        let value = Int(seconds.rounded())
        let text = String(format: "%d:%02d", value / 60, value % 60)
        return isRunningOut ? "-" + text : text
    }
}
