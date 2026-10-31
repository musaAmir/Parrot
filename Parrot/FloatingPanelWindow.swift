import AppKit
import SwiftUI
import Combine

enum PanelMetrics {
    static let height: CGFloat = 52
    static let inset: CGFloat = 8
    static let playbackWidth: CGFloat = 384
    static func recordingWidth(controls: Bool) -> CGFloat { controls ? 336 : 224 }
    static func windowSize(bodyWidth: CGFloat) -> CGSize {
        CGSize(width: bodyWidth + inset * 2, height: height + inset * 2)
    }
}

/// Shared placement and dragging behavior for both floating panels.
class FloatingPanelWindow: NSPanel {
    private let positionKey: String
    private let anchor: PanelPlacement.Anchor
    private var subscriptions = Set<AnyCancellable>()
    private var placing = false
    private var visibilityGeneration = UUID()

    init(size: CGSize, positionKey: String, anchor: PanelPlacement.Anchor) {
        self.positionKey = positionKey
        self.anchor = anchor
        super.init(contentRect: CGRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: self)
            .sink { [weak self] _ in self?.saveCenter() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.restorePosition() }.store(in: &subscriptions)
        restorePosition()
        orderOut(nil)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private var savedCenter: CGPoint? {
        guard let values = UserDefaults.standard.array(forKey: positionKey) as? [Double],
              values.count == 2, values.allSatisfy(\.isFinite) else { return nil }
        return CGPoint(x: values[0], y: values[1])
    }

    private func targetScreen(for point: CGPoint?) -> NSScreen? {
        let screens = NSScreen.screens
        if let point, let screen = screens.first(where: { $0.visibleFrame.contains(point) }) { return screen }
        return screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main ?? screens.first
    }

    private func restorePosition() {
        let center = savedCenter
        let screen = targetScreen(for: center)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let usableCenter = center.flatMap { screen.contains($0) ? $0 : nil }
        place(PanelPlacement.frame(size: frame.size, screen: screen, anchor: anchor, savedCenter: usableCenter))
    }

    private func place(_ rect: CGRect) {
        placing = true
        setFrame(rect, display: true)
        placing = false
    }

    private func saveCenter() {
        guard !placing else { return }
        UserDefaults.standard.set([Double(frame.midX), Double(frame.midY)], forKey: positionKey)
    }

    func installContent<Content: View>(_ rootView: Content) {
        let hosting = PanelHostingView(rootView: rootView)
        // Window geometry belongs to the panel; SwiftUI must not resize it first.
        hosting.sizingOptions = []
        contentView = hosting
    }

    func resizePanel(bodyWidth: CGFloat) {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let screen = targetScreen(for: center)?.visibleFrame ?? frame
        place(PanelPlacement.resized(frame, to: PanelMetrics.windowSize(bodyWidth: bodyWidth), screen: screen))
    }

    func finishDragging() {
        resizePanel(bodyWidth: frame.width - PanelMetrics.inset * 2)
        saveCenter()
    }

    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: positionKey)
        restorePosition()
    }

    func showPanel() {
        visibilityGeneration = UUID()
        restorePosition()
        alphaValue = 1
        orderFrontRegardless()
    }

    func hidePanel(releaseContent: Bool = false) {
        visibilityGeneration = UUID()
        let generation = visibilityGeneration
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.15
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.visibilityGeneration == generation else { return }
            self.orderOut(nil)
            if releaseContent { self.contentView = nil }
        })
    }
}

/// Tracks native mouse events without requiring this non-activating panel to become key.
private final class PanelWindowDrag {
    private weak var window: NSWindow?
    private var start: CGPoint = .zero
    private var origin: CGPoint = .zero
    func begin(_ event: NSEvent, window: NSWindow?) {
        self.window = window
        guard let window else { return }
        start = window.convertPoint(toScreen: event.locationInWindow)
        origin = window.frame.origin
    }
    func move(_ event: NSEvent) {
        guard let window else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        window.setFrameOrigin(CGPoint(x: origin.x + point.x - start.x, y: origin.y + point.y - start.y))
    }
    func end() { (window as? FloatingPanelWindow)?.finishDragging(); window = nil }
}

final class PanelHostingView<Content: View>: NSHostingView<Content> {
    private let panelDrag = PanelWindowDrag()
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { panelDrag.begin(event, window: window) }
    override func mouseDragged(with event: NSEvent) { panelDrag.move(event) }
    override func mouseUp(with event: NSEvent) { panelDrag.end() }
}

/// Explicit native drag target so SwiftUI controls do not swallow panel movement.
struct PanelDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragTargetView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private final class DragTargetView: NSView {
        override init(frame: NSRect) {
            super.init(frame: frame)
            setAccessibilityElement(true)
            setAccessibilityLabel("Drag panel to move")
            toolTip = "Drag to move the panel"
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        private let panelDrag = PanelWindowDrag()
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { panelDrag.begin(event, window: window) }
        override func mouseDragged(with event: NSEvent) { panelDrag.move(event) }
        override func mouseUp(with event: NSEvent) { panelDrag.end() }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.tertiaryLabelColor.setFill()
            for x in [bounds.midX - 3, bounds.midX + 3] {
                for y in [bounds.midY - 6, bounds.midY, bounds.midY + 6] {
                    NSBezierPath(ovalIn: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4)).fill()
                }
            }
        }
    }
}

struct PanelChrome: ViewModifier {
    @ObservedObject var audioManager: AudioManager
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: audioManager.panelShape.cornerRadius, style: .continuous)
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(.primary.opacity(0.12), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
            .padding(PanelMetrics.inset)
    }
}

struct PanelIconButton: View {
    let symbol: String
    let label: String
    var action: () -> Void
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
        .help(label)
    }
}
