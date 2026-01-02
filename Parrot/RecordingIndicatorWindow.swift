//
//  RecordingIndicatorWindow.swift
//  Parrot
//
//  Floating window that displays recording indicator with animated waveform
//

import Cocoa
import SwiftUI

// Observable class to control animation state from window
class RecordingAnimationState: ObservableObject {
    @Published var isAnimating: Bool = false
}

class RecordingIndicatorWindow: NSWindow {
    private var initialLocation: NSPoint = .zero
    weak var appDelegate: AppDelegate?
    private let animationState = RecordingAnimationState()

    init(appDelegate: AppDelegate? = nil) {
        self.appDelegate = appDelegate
        let screenFrame = NSScreen.main?.frame ?? NSRect.zero
        let windowWidth: CGFloat = 180
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

        let hostingView = NSHostingView(rootView: RecordingIndicatorView(animationState: animationState))
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
        animationState.isAnimating = true

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.animator().alphaValue = 1.0
        })
    }

    func hide() {
        animationState.isAnimating = false

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }
}

struct RecordingIndicatorView: View {
    @ObservedObject var animationState: RecordingAnimationState
    @State private var isPulsing: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(isPulsing ? 1.0 : 0.7))

            Text("Recording")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))

            if animationState.isAnimating {
                TimelineView(.animation(minimumInterval: 0.05)) { timeline in
                    HStack(spacing: 3) {
                        ForEach(0..<5, id: \.self) { index in
                            WaveformBar(index: index, date: timeline.date)
                        }
                    }
                }
            } else {
                // Static waveform when not animating
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(Color.white.opacity(0.8))
                            .frame(width: 3, height: 10)
                            .frame(height: 22)
                    }
                }
            }
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
        .onChange(of: animationState.isAnimating) { _, isAnimating in
            if isAnimating {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    isPulsing = false
                }
            }
        }
    }
}

struct WaveformBar: View {
    let index: Int
    let date: Date

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(Color.white.opacity(0.8))
            .frame(width: 3, height: barHeight)
            .frame(height: 22)
    }

    private var barHeight: CGFloat {
        let phase = date.timeIntervalSinceReferenceDate * 5.0
        let offset = Double(index) * 0.5
        let amplitude = sin(phase + offset) * 0.5 + 0.5
        return 6 + amplitude * 16
    }
}
