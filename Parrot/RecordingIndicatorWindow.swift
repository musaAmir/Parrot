//
//  RecordingIndicatorWindow.swift
//  Parrot
//
//  Floating window that displays recording indicator with animated waveform
//

import Cocoa
import SwiftUI

class RecordingIndicatorWindow: NSWindow {
    private var animationTimer: Timer?
    private var initialLocation: NSPoint = .zero
    weak var appDelegate: AppDelegate?

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

        let hostingView = NSHostingView(rootView: RecordingIndicatorView())
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
        startAnimation()

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
            self.stopAnimation()
        })
    }

    private func startAnimation() {
        if let contentView = self.contentView as? NSHostingView<RecordingIndicatorView> {
            contentView.rootView.isAnimating = true
        }
    }

    private func stopAnimation() {
        if let contentView = self.contentView as? NSHostingView<RecordingIndicatorView> {
            contentView.rootView.isAnimating = false
        }
    }
}

struct RecordingIndicatorView: View {
    @State var isAnimating: Bool = false
    @State private var phase: CGFloat = 0
    @State private var opacity: Double = 0.7

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(opacity))

            Text("Recording")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))

            HStack(spacing: 3) {
                ForEach(0..<5) { index in
                    WaveformBar(index: index, phase: phase)
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
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            isAnimating = false
        }
    }

    private func startAnimation() {
        isAnimating = true

        Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { timer in
            guard isAnimating else {
                timer.invalidate()
                return
            }
            withAnimation(.linear(duration: 0.04)) {
                phase += 0.2
            }
        }

        withAnimation(
            .easeInOut(duration: 1.0)
            .repeatForever(autoreverses: true)
        ) {
            opacity = 1.0
        }
    }
}

struct WaveformBar: View {
    let index: Int
    let phase: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(Color.white.opacity(0.8))
            .frame(width: 3, height: barHeight)
            .frame(height: 22)
    }

    private var barHeight: CGFloat {
        let offset = CGFloat(index) * 0.5
        let amplitude = sin(phase + offset) * 0.5 + 0.5
        return 6 + amplitude * 16
    }
}
