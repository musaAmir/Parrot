//
//  ShortcutRecorder.swift
//  Parrot
//
//  Custom view for recording keyboard shortcuts
//

import SwiftUI
import AppKit

struct ShortcutRecorder: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    @Binding var keyCode: UInt16
    @Binding var modifierFlags: NSEvent.ModifierFlags

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.onShortcutCapture = { keyCode, flags in
            self.keyCode = keyCode
            self.modifierFlags = flags
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderView, context: Context) {
        nsView.isCaptureEnabled = isEnabled
        nsView.keyCode = keyCode
        nsView.modifierFlags = modifierFlags
        nsView.setAccessibilityValue(nsView.shortcutString())
        nsView.needsDisplay = true
    }
}

class ShortcutRecorderView: NSView {
    var keyCode: UInt16 = 5
    var modifierFlags: NSEvent.ModifierFlags = .option
    var onShortcutCapture: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    var isCaptureEnabled = true {
        didSet { if !isCaptureEnabled && isRecording { cancelRecording() } }
    }
    var isRecording = false
    var isHovering = false

    private var pulseAnimation: CABasicAnimation?
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func setup() {
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Recording shortcut")
        setAccessibilityHelp("Press to choose a shortcut. Escape cancels.")
        wantsLayer = true

        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existingArea = trackingArea {
            removeTrackingArea(existingArea)
        }

        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        if let area = trackingArea {
            addTrackingArea(area)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateAppearance(animated: true)
    }

    override var acceptsFirstResponder: Bool { isCaptureEnabled }

    override func accessibilityPerformPress() -> Bool {
        guard isCaptureEnabled else { return false }
        beginCapture()
        return true
    }

    private func beginCapture() {
        isRecording = true
        startPulseAnimation()
        updateAppearance(animated: true)
        needsDisplay = true
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            cancelRecording()
        }
        return super.resignFirstResponder()
    }

    private func cancelRecording() {
        isRecording = false
        stopPulseAnimation()
        updateAppearance(animated: true)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isCaptureEnabled else { return }
        beginCapture()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            self.layer?.transform = CATransform3DMakeScale(0.98, 0.98, 1)
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                self.layer?.transform = CATransform3DIdentity
            })
        })
    }

    override func keyDown(with event: NSEvent) {
        guard isCaptureEnabled else { return }
        if !isRecording {
            if event.keyCode == 36 || event.keyCode == 49 { beginCapture() }
            else { super.keyDown(with: event) }
            return
        }

        if event.keyCode == 53 {  // Escape cancels
            cancelRecording()
            return
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])

        if modifiers.isEmpty {
            flashInvalid()
            return
        }

        keyCode = event.keyCode
        modifierFlags = modifiers
        onShortcutCapture?(keyCode, modifiers)
        cancelRecording()
    }

    private func updateAppearance(animated: Bool) { needsDisplay = true }

    private func startPulseAnimation() {
        let pulse = CABasicAnimation(keyPath: "borderWidth")
        pulse.fromValue = 2.5
        pulse.toValue = 3.5
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        layer?.add(pulse, forKey: "borderPulse")
        pulseAnimation = pulse
    }

    private func stopPulseAnimation() {
        layer?.removeAnimation(forKey: "borderPulse")
        pulseAnimation = nil
    }

    private func flashInvalid() {
        let originalColor = layer?.borderColor

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            self.layer?.borderColor = NSColor.systemRed.cgColor
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                self.layer?.borderColor = originalColor
            })
        })
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let text = isRecording ? "Press shortcut…" : shortcutString()
        let keys = isRecording ? [text] : text.split(separator: " ").flatMap { part in
            part.count > 1 && part.allSatisfy({ "⌃⌥⇧⌘".contains($0) }) ? part.map(String.init) : [String(part)]
        }
        let widths = keys.map { max(22, ceil(($0 as NSString).size(withAttributes: [.font: font]).width) + 12) }
        var x = bounds.maxX - widths.reduce(0, +) - CGFloat(max(0, keys.count - 1)) * 4
        for (index, key) in keys.enumerated() {
            let rect = NSRect(x: x, y: bounds.midY - 10, width: widths[index], height: 20)
            (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.25) : NSColor.quaternaryLabelColor).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            let size = (key as NSString).size(withAttributes: [.font: font])
            (key as NSString).draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: [.font: font, .foregroundColor: NSColor.labelColor])
            x += widths[index] + 4
        }
    }

    func shortcutString() -> String {
        KeyCodeFormatter.shortcutString(keyCode: keyCode, modifierFlags: modifierFlags)
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 140, height: 26)
    }

    override var focusRingMaskBounds: NSRect {
        return bounds
    }

    override func drawFocusRingMask() {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        path.fill()
    }
}
