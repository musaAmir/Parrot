//
//  ShortcutRecorder.swift
//  Parrot
//
//  Custom view for recording keyboard shortcuts
//

import SwiftUI
import AppKit

struct ShortcutRecorder: NSViewRepresentable {
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
        nsView.keyCode = keyCode
        nsView.modifierFlags = modifierFlags
    }
}

class ShortcutRecorderView: NSView {
    var keyCode: UInt16 = 5
    var modifierFlags: NSEvent.ModifierFlags = .option
    var onShortcutCapture: ((UInt16, NSEvent.ModifierFlags) -> Void)?
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
        wantsLayer = true

        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        layer?.borderWidth = 1.5
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous

        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.08
        layer?.shadowOffset = CGSize(width: 0, height: 1)
        layer?.shadowRadius = 3

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

    override var acceptsFirstResponder: Bool { true }

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
        isRecording = true
        startPulseAnimation()
        updateAppearance(animated: true)
        needsDisplay = true
        window?.makeFirstResponder(self)

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
        guard isRecording else { return }

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

    private func updateAppearance(animated: Bool) {
        let duration = animated ? 0.2 : 0

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            if isRecording {
                self.layer?.borderColor = NSColor.controlAccentColor.cgColor
                self.layer?.borderWidth = 2.5
                self.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
                self.layer?.shadowOpacity = 0.15
            } else if isHovering {
                self.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.5).cgColor
                self.layer?.borderWidth = 1.5
                self.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.7).cgColor
                self.layer?.shadowOpacity = 0.12
            } else {
                self.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
                self.layer?.borderWidth = 1.5
                self.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
                self.layer?.shadowOpacity = 0.08
            }
        })
    }

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

        let text: String
        let textColor: NSColor

        if isRecording {
            text = "Press your shortcut..."
            textColor = NSColor.controlAccentColor
        } else {
            text = shortcutString()
            textColor = NSColor.labelColor
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let fontSize: CGFloat = isRecording ? 14 : 16
        let fontWeight: NSFont.Weight = isRecording ? .medium : .semibold

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: fontWeight),
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]

        let textRect = NSRect(x: 0, y: (bounds.height - 22) / 2, width: bounds.width, height: 22)
        text.draw(in: textRect, withAttributes: attributes)
    }

    func shortcutString() -> String {
        KeyCodeFormatter.shortcutString(keyCode: keyCode, modifierFlags: modifierFlags)
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 220, height: 44)
    }

    override var focusRingMaskBounds: NSRect {
        return bounds
    }

    override func drawFocusRingMask() {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        path.fill()
    }
}
