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

    init(audioManager: AudioManager) {
        self.audioManager = audioManager
        let screenFrame = NSScreen.main?.frame ?? NSRect.zero
        let windowWidth: CGFloat = 200
        let windowHeight: CGFloat = 6

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
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let view = PlaybackIndicatorView(progress: audioManager.playbackProgress)
        progressView = NSHostingView(rootView: view)
        self.contentView = progressView

        self.orderOut(nil)
        setupBindings()
    }

    private func setupBindings() {
        audioManager?.$playbackProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.progressView?.rootView.progress = progress
            }
            .store(in: &cancellables)
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
            context.duration = 0.15
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }
}

struct PlaybackIndicatorView: View {
    var progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(.white.opacity(0.2))

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(.white.opacity(0.8))
                    .frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: 6)
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }
}
