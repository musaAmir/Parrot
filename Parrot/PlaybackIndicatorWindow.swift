import AppKit
import SwiftUI

class PlaybackIndicatorWindow: FloatingPanelWindow {
    private let audioManager: AudioManager
    var onReplay: (() -> Void)?
    var onClose: (() -> Void)?

    init(audioManager: AudioManager) {
        self.audioManager = audioManager
        super.init(size: PanelMetrics.windowSize(bodyWidth: PanelMetrics.playbackWidth),
                   positionKey: "playbackPanelCenter", anchor: .bottom)
        setAccessibilityTitle("Parrot Playback")
        installContent(PlaybackIndicatorView(audioManager: audioManager,
            onReplay: { [weak self] in self?.onReplay?() }, onClose: { [weak self] in self?.onClose?() }))
    }
    func show() { showPanel() }
    func hide() { hidePanel() }
}

struct PlaybackIndicatorView: View {
    @ObservedObject var audioManager: AudioManager
    var preview = false
    var onReplay: (() -> Void)?
    var onClose: (() -> Void)?

    private var playing: Bool { audioManager.isPlaying && !audioManager.isPaused }
    var body: some View {
        HStack(spacing: 10) {
            PanelDragHandle().frame(width: 12, height: 28).allowsHitTesting(!preview)
            PanelIconButton(symbol: "arrow.counterclockwise", label: "Replay recording") {
                audioManager.replayRecording()
                onReplay?()
            }.disabled(preview)
            PanelIconButton(symbol: playing ? "pause.fill" : "play.fill", label: playing ? "Pause playback" : "Play recording") {
                audioManager.togglePlayback()
                onReplay?()
            }.disabled(preview)
            VStack(alignment: .leading, spacing: 0) {
                Text(preview ? "0:08 / 0:24" : audioManager.playbackTimeLabel)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit().foregroundStyle(.secondary)
                Slider(value: Binding(get: { preview ? 0.33 : audioManager.playbackProgress },
                                      set: { audioManager.seek(to: $0); onReplay?() }), in: 0...1) {
                    Text("Playback position")
                }
                .labelsHidden().controlSize(.mini).disabled(preview)
            }
            .frame(maxWidth: .infinity)
            Divider().frame(height: 20)
            PanelIconButton(symbol: "xmark", label: "Close panel and stop playback") { onClose?() }
                .disabled(preview)
        }
        .padding(.horizontal, 14)
        .frame(width: PanelMetrics.playbackWidth, height: PanelMetrics.height)
        .modifier(PanelChrome(audioManager: audioManager))
    }
}
