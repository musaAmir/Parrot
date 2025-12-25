//
//  PlaybackIndicatorWindow.swift
//  Parrot
//
//  Minimalistic playback progress bar at the bottom of the screen
//

import Cocoa
import SwiftUI
import Combine

class PlaybackIndicatorWindow: NSWindow {
    private var audioManager: AudioManager?
    private var cancellables = Set<AnyCancellable>()
    private var progressView: NSHostingView<PlaybackIndicatorView>?
    var onReplay: (() -> Void)?

    init(audioManager: AudioManager) {
        self.audioManager = audioManager
        let screenFrame = NSScreen.main?.frame ?? NSRect.zero
        let windowWidth: CGFloat = 340 // Increased width for controls
        let windowHeight: CGFloat = 40 // Increased height for controls

        let xPos = (screenFrame.width - windowWidth) / 2
        let yPos: CGFloat = 40

        let contentRect = NSRect(
            x: xPos,
            y: yPos,
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
        self.ignoresMouseEvents = false // Allow interaction
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let view = PlaybackIndicatorView(audioManager: audioManager, onReplay: { [weak self] in
            self?.onReplay?()
        })
        progressView = NSHostingView(rootView: view)
        self.contentView = progressView

        self.orderOut(nil)
        setupBindings()
    }

    private func setupBindings() {
        // No longer needed as we use ObservedObject in the view
    }

    override var canBecomeKey: Bool {
        return true
    }

    func show() {
        self.alphaValue = 0
        self.orderFront(nil)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            self.animator().alphaValue = 1.0
        })
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }
}

struct PlaybackIndicatorView: View {
    @ObservedObject var audioManager: AudioManager
    var onReplay: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // Rewind Button
            Button(action: {
                audioManager.replayRecording()
                onReplay?()
            }) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)

            // Play/Pause Button
            Button(action: {
                audioManager.togglePlayback()
            }) {
                Image(systemName: audioManager.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            
            // Progress Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(.white.opacity(0.2))

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(.white.opacity(0.8))
                        .frame(width: geometry.size.width * audioManager.playbackProgress)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let progress = min(max(value.location.x / geometry.size.width, 0), 1)
                            audioManager.seek(to: progress)
                        }
                )
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }
}
