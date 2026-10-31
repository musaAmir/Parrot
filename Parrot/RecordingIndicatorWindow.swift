//
//  RecordingIndicatorWindow.swift
//  Parrot
//
//  Floating window that displays recording indicator with animated waveform
//

import Cocoa
import SwiftUI
import Combine

class RecordingIndicatorWindow: FloatingPanelWindow {
    private let audioManager: AudioManager
    private var controlSubscription: AnyCancellable?
    weak var appDelegate: AppDelegate?

    init(audioManager: AudioManager, appDelegate: AppDelegate? = nil) {
        self.audioManager = audioManager
        self.appDelegate = appDelegate
        super.init(size: PanelMetrics.windowSize(bodyWidth: PanelMetrics.recordingWidth(controls: audioManager.showRecordingControls)),
                   positionKey: "recordingPanelCenter", anchor: .top)
        setAccessibilityTitle("Parrot Recording")
        controlSubscription = audioManager.$showRecordingControls.removeDuplicates().sink { [weak self] enabled in
            // Published emits before the value changes; lay out after SwiftUI can read it.
            DispatchQueue.main.async { self?.resizePanel(bodyWidth: PanelMetrics.recordingWidth(controls: enabled)) }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settings.target = self; menu.addItem(settings)
        let reset = NSMenuItem(title: "Reset Position", action: #selector(resetFromMenu), keyEquivalent: "")
        reset.target = self; menu.addItem(reset)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Parrot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp; menu.addItem(quit)
        NSMenu.popUpContextMenu(menu, with: event, for: contentView!)
    }
    @objc private func openSettingsFromMenu() { appDelegate?.openSettings() }
    @objc private func resetFromMenu() { resetPosition() }

    func show() {
        if contentView == nil || !(contentView is PanelHostingView<RecordingIndicatorView>) {
            installContent(RecordingIndicatorView(audioManager: audioManager))
        }
        showPanel()
    }
    func hide() { hidePanel(releaseContent: true) }
}

/// Recording indicator showing the live microphone level and elapsed time.
///
/// The bars used to be a `sin()` curve on a timer, so they looked identical
/// whether you were talking or the mic was muted. They now scroll a short
/// history of real level readings from `AVAudioRecorder`'s meters.
struct RecordingIndicatorView: View {
    @ObservedObject var audioManager: AudioManager
    var preview = false
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
            PanelDragHandle().frame(width: 12, height: 28).allowsHitTesting(!preview)
            Image(systemName: "circle.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(audioManager.isRecordingPaused ? .orange : .red.opacity(isPulsing ? 1.0 : 0.45))

            HStack(spacing: 3) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(.primary.opacity(0.8))
                        .frame(width: 3, height: 3 + level * (Self.barHeight - 3))
                        .frame(height: Self.barHeight)
                }
            }
            .animation(.linear(duration: 0.05), value: levels)

            Text(preview ? "0:12" : (audioManager.isPreparingToRecord ? "Starting…" : (audioManager.isRecordingPaused ? "Paused" : timeLabel)))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isRunningOut ? .orange : .primary)
                .frame(minWidth: 36)
            Spacer(minLength: 0)
            if audioManager.showRecordingControls {
                Divider().frame(height: 20)
                PanelIconButton(symbol: audioManager.isRecordingPaused ? "play.fill" : "pause.fill",
                                label: audioManager.isRecordingPaused ? "Resume recording" : "Pause recording") {
                    audioManager.toggleRecordingPause()
                }.disabled(preview || audioManager.isPreparingToRecord)
                PanelIconButton(symbol: "stop.fill", label: audioManager.isPreparingToRecord ? "Cancel recording" : "Stop recording and listen") {
                    audioManager.stopRecordingAndPlayback()
                }.disabled(preview)
            }
        }
        .padding(.horizontal, 14)
        .frame(width: PanelMetrics.recordingWidth(controls: audioManager.showRecordingControls), height: PanelMetrics.height)
        .modifier(PanelChrome(audioManager: audioManager))
        .onAppear {
            if preview { levels = [0.2, 0.4, 0.7, 0.35, 0.6, 0.9, 0.5, 0.25, 0.5, 0.75, 0.4, 0.6, 0.3, 0.15] }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .onReceive(audioManager.$recordingLevel) { level in
            guard !preview else { return }
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
