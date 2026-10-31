import AppKit
import SwiftUI
import Combine
import ServiceManagement

// The same native window, sidebar, card spacing and controls used by Hush.
final class ParrotSettingsController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    enum Page: Int, CaseIterable {
        case general, appearance, shortcuts, audio, recordings, permissions
        var title: String { ["General", "Appearance", "Shortcuts", "Audio", "Recordings", "Permissions"][rawValue] }
        var symbol: String { ["gearshape.fill", "circle.lefthalf.filled", "command", "speaker.wave.2.fill", "waveform", "lock.shield.fill"][rawValue] }
        var color: NSColor { [.systemGray, .systemPink, .systemTeal, .systemBlue, .systemOrange, .systemIndigo][rawValue] }
    }
    private let audio: AudioManager
    private let permissions: PermissionManager
    private let updates: UpdateController
    private let save: (URL) -> Void
    private let navigation = NSTableView()
    private let scroll = NSScrollView()
    private var selected: Page = .general
    private var subscriptions = Set<AnyCancellable>()
    private var seekSlider: NSSlider?
    private let width: CGFloat = 512
    private static let cardColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.05) : NSColor(white: 0, alpha: 0.04)
    }

    init(audio: AudioManager, permissions: PermissionManager, updates: UpdateController, save: @escaping (URL) -> Void) {
        self.audio = audio; self.permissions = permissions; self.updates = updates; self.save = save
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 640), styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "General"; window.isReleasedWhenClosed = false
        window.toolbar = NSToolbar(identifier: "ParrotSettings")
        window.toolbarStyle = .unified
        window.contentMinSize = NSSize(width: 780, height: 480)
        super.init(window: window)

        let sidebar = NSViewController(); sidebar.view = NSView()
        navigation.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section")))
        navigation.headerView = nil; navigation.style = .sourceList; navigation.rowHeight = 32
        navigation.intercellSpacing = NSSize(width: 0, height: 2); navigation.backgroundColor = .clear
        navigation.allowsEmptySelection = false; navigation.allowsMultipleSelection = false
        navigation.focusRingType = .none; navigation.delegate = self; navigation.dataSource = self
        navigation.setAccessibilityLabel("Settings sections")
        let sidebarScroll = NSScrollView(); sidebarScroll.drawsBackground = false; sidebarScroll.documentView = navigation
        sidebarScroll.automaticallyAdjustsContentInsets = false
        sidebarScroll.translatesAutoresizingMaskIntoConstraints = false; sidebar.view.addSubview(sidebarScroll)
        NSLayoutConstraint.activate([
            sidebarScroll.topAnchor.constraint(equalTo: sidebar.view.safeAreaLayoutGuide.topAnchor, constant: 6),
            sidebarScroll.leadingAnchor.constraint(equalTo: sidebar.view.leadingAnchor),
            sidebarScroll.trailingAnchor.constraint(equalTo: sidebar.view.trailingAnchor),
            sidebarScroll.bottomAnchor.constraint(equalTo: sidebar.view.bottomAnchor, constant: -12)
        ])
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        let detail = NSViewController(); detail.view = scroll
        let split = NSSplitViewController()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 200; sidebarItem.maximumThickness = 230; sidebarItem.canCollapse = false
        split.addSplitViewItem(sidebarItem)
        let detailItem = NSSplitViewItem(viewController: detail); detailItem.titlebarSeparatorStyle = .none
        split.addSplitViewItem(detailItem); window.contentViewController = split
        navigation.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        window.setContentSize(NSSize(width: 800, height: 640)); window.center()
        audio.$isRecording.removeDuplicates().dropFirst().sink { [weak self] _ in self?.refreshSoon() }.store(in: &subscriptions)
        audio.$isPreparingToRecord.removeDuplicates().dropFirst().sink { [weak self] _ in self?.refreshSoon() }.store(in: &subscriptions)
        audio.$isRecordingPaused.removeDuplicates().dropFirst().sink { [weak self] _ in self?.refreshSoon() }.store(in: &subscriptions)
        audio.$isPlaying.removeDuplicates().dropFirst().sink { [weak self] _ in self?.refreshSoon() }.store(in: &subscriptions)
        audio.$isPaused.removeDuplicates().dropFirst().sink { [weak self] _ in self?.refreshSoon() }.store(in: &subscriptions)
        audio.$lastError.removeDuplicates().dropFirst().sink { [weak self] _ in self?.refreshSoon() }.store(in: &subscriptions)
        audio.$playbackProgress.sink { [weak self] value in self?.seekSlider?.doubleValue = value }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).sink { [weak self] _ in
            self?.permissions.refreshPermissions(); self?.render()
        }.store(in: &subscriptions)
        render()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func select(_ page: Page) { navigation.selectRowIndexes(IndexSet(integer: page.rawValue), byExtendingSelection: false) }
    func numberOfRows(in tableView: NSTableView) -> Int { Page.allCases.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let page = Page.allCases[row], cell = NSTableCellView()
        let badge = NSView(); badge.wantsLayer = true; badge.layer?.backgroundColor = page.color.cgColor
        badge.layer?.cornerRadius = 6; badge.layer?.cornerCurve = .continuous
        let image = symbol(page.symbol, size: 12); image.contentTintColor = .white
        let text = NSTextField(labelWithString: page.title); cell.textField = text
        [badge, image, text].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        badge.addSubview(image); cell.addSubview(badge); cell.addSubview(text)
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4), badge.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 22), badge.heightAnchor.constraint(equalToConstant: 22),
            image.centerXAnchor.constraint(equalTo: badge.centerXAnchor), image.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            text.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 8), text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8)
        ])
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let page = Page(rawValue: navigation.selectedRow) else { return }
        window?.makeFirstResponder(navigation); selected = page; render()
    }
    private func refreshSoon() { DispatchQueue.main.async { [weak self] in self?.render() } }
    private func render() {
        guard isWindowLoaded else { return }
        let origin = scroll.contentView.bounds.origin
        seekSlider = nil
        let content: NSStackView
        switch selected {
        case .general: content = general()
        case .appearance: content = appearance()
        case .shortcuts: content = shortcuts()
        case .audio: content = audioPage()
        case .recordings: content = recordings()
        case .permissions: content = permissionPage()
        }
        if let error = audio.lastError { content.insertArrangedSubview(detail(error), at: 0) }
        let document = SettingsDocumentView()
        content.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(content); scroll.documentView = document
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            content.widthAnchor.constraint(equalToConstant: width + 28), content.centerXAnchor.constraint(equalTo: document.centerXAnchor),
            content.topAnchor.constraint(equalTo: document.topAnchor, constant: 12), content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -28)
        ])
        window?.title = selected.title; window?.layoutIfNeeded()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(-scroll.contentInsets.top, min(origin.y, document.frame.height - scroll.contentSize.height))))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    private func toggle(_ title: String, _ key: ReferenceWritableKeyPath<AudioManager, Bool>, refresh: Bool = false) -> NSView {
        let control = SettingsSwitch(); control.state = audio[keyPath: key] ? .on : .off; control.setAccessibilityLabel(title)
        control.changed = { [weak self] value in
            guard let self else { return }; self.audio[keyPath: key] = value
            if refresh { self.refreshSoon() }
        }
        return row(label(title), control)
    }
    private func button(_ title: String, _ action: @escaping () -> Void) -> NSButton {
        let button = SettingsButton(title: title, target: nil, action: nil); button.pressed = action; button.target = button; button.action = NSSelectorFromString("invoke"); return button
    }
    private func slider(_ title: String, _ key: ReferenceWritableKeyPath<AudioManager, Double>, range: ClosedRange<Double>, format: @escaping (Double) -> String) -> NSView {
        let value = NSTextField(labelWithString: format(audio[keyPath: key])); valueLabel(value)
        let control = SettingsSlider(value: audio[keyPath: key], minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
        control.target = control; control.action = NSSelectorFromString("invoke"); control.isContinuous = true; control.setAccessibilityLabel(title); control.widthAnchor.constraint(equalToConstant: 220).isActive = true
        control.changed = { [weak self] number in self?.audio[keyPath: key] = number; value.stringValue = format(number) }
        return row(label(title), control, value)
    }
    private func general() -> NSStackView {
        let stack = page()
        let login = SettingsSwitch(); login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.setAccessibilityLabel("Launch Parrot at login")
        login.changed = { [weak self] enabled in
            do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
            catch { NSAlert(error: error).runModal() }
            self?.refreshSoon()
        }
        stack.addArrangedSubview(group("Startup", [row(label("Launch Parrot at login"), login)]))
        stack.addArrangedSubview(group("Recording", [toggle("Keep recent recordings", \.keepRecordings), slider("Maximum length", \.maxRecordingDuration, range: 10...600) { String(format: "%d:%02d", Int($0) / 60, Int($0) % 60) }], footer: [detail("Your latest 10 takes stay on this Mac. Save a copy from Recordings to keep a take permanently.")]))
        stack.addArrangedSubview(group("Feedback", [toggle("Play recording sounds", \.playFeedbackSounds)], footer: [detail("Recording starts after the start cue and a short echo gap. Wait for the timer before speaking. Turn sounds off for an immediate start.")]))
        let automatic = SettingsSwitch(); automatic.state = updates.automaticallyChecksForUpdates ? .on : .off
        automatic.setAccessibilityLabel("Check for updates automatically")
        automatic.changed = { [weak self] in self?.updates.setAutomaticallyChecksForUpdates($0) }
        let check = button("Check Now") { [weak self] in self?.updates.checkForUpdates() }; check.isEnabled = updates.canCheckForUpdates
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        stack.addArrangedSubview(group("Updates", [row(label("Check for updates automatically"), automatic), row(label("Parrot \(version)"), check)], footer: [detail(updates.startupError ?? "Updates come from Parrot releases on GitHub.")]))
        return stack
    }
    private func appearance() -> NSStackView {
        let stack = page()
        let preview = NSHostingView(rootView: RecordingIndicatorView(audioManager: audio, preview: true))
        preview.widthAnchor.constraint(equalToConstant: width + 28).isActive = true; preview.heightAnchor.constraint(equalToConstant: 100).isActive = true
        stack.addArrangedSubview(preview)
        stack.addArrangedSubview(group("Recording panel", [toggle("Show pause and stop buttons", \.showRecordingControls, refresh: true)], footer: [detail("Pause keeps the current take open. Stop finishes the take and plays it back. Drag the panel to move it.")]))
        stack.addArrangedSubview(group("Playback panel", [toggle("Show playback controls", \.showPlaybackIndicator), slider("Dismiss after playback", \.overlayDismissDelay, range: 1...20) { "\(Int($0)) s" }]))
        stack.addArrangedSubview(group("Visibility", [toggle("Show in Dock", \.showDockIcon), toggle("Show in menu bar", \.showMenuBarIcon)], footer: [detail("At least one icon stays visible so you can always reopen Parrot.")]))
        return stack
    }
    private func shortcuts() -> NSStackView {
        let stack = page()
        for hold in [true, false] {
            let recorder = ShortcutRecorderView()
            recorder.keyCode = hold ? audio.shortcutKeyCode : audio.toggleShortcutKeyCode
            recorder.modifierFlags = hold ? audio.shortcutModifierFlags : audio.toggleShortcutModifierFlags
            recorder.isCaptureEnabled = hold ? audio.holdModeEnabled : audio.toggleModeEnabled
            recorder.alphaValue = recorder.isCaptureEnabled ? 1 : 0.45
            recorder.widthAnchor.constraint(equalToConstant: 140).isActive = true; recorder.heightAnchor.constraint(equalToConstant: 26).isActive = true
            recorder.setAccessibilityLabel(hold ? "Hold to record shortcut" : "Tap to record shortcut")
            recorder.onShortcutCapture = { [weak self] code, flags in
                guard let self else { return }
                if hold { self.audio.shortcutKeyCode = code; self.audio.shortcutModifierFlags = flags }
                else { self.audio.toggleShortcutKeyCode = code; self.audio.toggleShortcutModifierFlags = flags }
                self.refreshSoon()
            }
            stack.addArrangedSubview(group(hold ? "Hold" : "Tap", [toggle(hold ? "Hold to record" : "Tap to record", hold ? \.holdModeEnabled : \.toggleModeEnabled, refresh: true), row(label("Shortcut"), recorder)], footer: [detail(hold ? "Hold while speaking. Release to finish and listen." : "Tap to start. Tap again to finish and listen. Holding for 1.5 seconds uses hold mode.")]))
        }
        if audio.holdModeEnabled && audio.toggleModeEnabled && audio.shortcutKeyCode == audio.toggleShortcutKeyCode && audio.shortcutModifierFlags == audio.toggleShortcutModifierFlags {
            stack.addArrangedSubview(detail("These shortcuts match. Choose a different shortcut for one mode; only Hold will respond."))
        }
        stack.addArrangedSubview(detail("Click a shortcut, then press a key with Control, Option or Command. Escape cancels."))
        return stack
    }
    private func device(_ title: String, devices: [AudioDevice], key: ReferenceWritableKeyPath<AudioManager, String?>) -> NSView {
        let menu = SettingsPopup(frame: .zero, pullsDown: false); let ids: [String?] = [nil] + devices.map { Optional($0.uid) }
        menu.addItems(withTitles: ["System Default"] + devices.map(\.name)); menu.setAccessibilityLabel(title)
        if let index = ids.firstIndex(of: audio[keyPath: key]) { menu.selectItem(at: index) }
        else { menu.addItem(withTitle: "Unavailable device"); menu.selectItem(at: ids.count) }
        menu.changed = { [weak self] index in if ids.indices.contains(index) { self?.audio[keyPath: key] = ids[index] } }
        return row(label(title), menu)
    }
    private func audioPage() -> NSStackView {
        let stack = page()
        stack.addArrangedSubview(group("Devices", [device("Microphone", devices: audio.getAvailableInputDevices(), key: \.selectedInputDeviceUID), device("Playback output", devices: audio.getAvailableOutputDevices(), key: \.selectedOutputDeviceID), row(label("Connected devices"), button("Refresh") { [weak self] in self?.render() })]))
        stack.addArrangedSubview(group("Playback", [slider("Playback delay", \.playbackDelay, range: 0...5) { String(format: "%.1f s", $0) }, slider("Volume", \.playbackVolume, range: 0...1) { "\(Int($0 * 100))%" }]))
        return stack
    }
    private func recordings() -> NSStackView {
        let stack = page()
        let record = button(audio.isPreparingToRecord ? "Cancel" : (audio.isRecording ? "Stop & Listen" : "Record")) { [weak self] in
            guard let self else { return }
            if self.audio.isRecording { self.audio.stopRecordingAndPlayback() } else { self.audio.startRecording() }
        }
        let pause = button(audio.isRecordingPaused ? "Resume" : "Pause") { [weak self] in self?.audio.toggleRecordingPause() }
        pause.isEnabled = audio.isRecording && !audio.isPreparingToRecord
        stack.addArrangedSubview(group("Recording", [row(label(audio.isPreparingToRecord ? "Starting after the cue…" : audio.isRecording ? (audio.isRecordingPaused ? "Recording paused" : "Recording in progress") : "Ready for your next take"), pause, record)]))
        let takes = audio.recentRecordings().filter { !audio.isRecording || $0.url != audio.currentRecordingURL }
        var rows: [NSView] = []
        for take in takes {
            let active = audio.currentRecordingURL == take.url && audio.isPlaying
            let play = button(active && !audio.isPaused ? "Pause" : "Play") { [weak self] in
                guard let self else { return }
                if active { self.audio.togglePlayback() } else { self.audio.play(url: take.url) }
            }; play.isEnabled = !audio.isRecording
            let name = vertical(spacing: 2)
            name.addArrangedSubview(label(take.createdAt.formatted(date: .abbreviated, time: .shortened)))
            name.addArrangedSubview(detail(take.displayName + (active ? (audio.isPaused ? " · Paused" : " · Playing") : "")))
            rows.append(row(name, play, button("Save…") { [weak self] in self?.save(take.url) }))
            if active {
                let slider = SettingsSlider(value: audio.playbackProgress, minValue: 0, maxValue: 1, target: nil, action: nil)
                slider.target = slider; slider.action = NSSelectorFromString("invoke"); slider.isContinuous = true; slider.setAccessibilityLabel("Playback position")
                slider.widthAnchor.constraint(equalToConstant: 350).isActive = true
                slider.changed = { [weak self] in self?.audio.seek(to: $0) }; seekSlider = slider
                rows.append(row(label("Position"), slider, button("Stop") { [weak self] in self?.audio.stopPlayback() }))
            }
        }
        if rows.isEmpty { rows = [row(detail("No finished takes yet. Record something to listen again or save a copy."))] }
        stack.addArrangedSubview(group("Recent Takes", rows, footer: [detail("Parrot keeps up to 10 recent takes when retention is enabled. Save a copy to keep a take permanently.")]))
        stack.addArrangedSubview(row(label("Recording files"), button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([RecordingStore.directory]) }))
        return stack
    }
    private func permissionPage() -> NSStackView {
        let stack = page()
        let controlTitle = PermissionManager.controlPermissionTitle
        for (title, status, kind) in [("Microphone", permissions.microphoneStatus, "microphone"), (controlTitle, permissions.accessibilityStatus, "accessibility")] {
            let text = label(status.displayText); text.textColor = status.color
            stack.addArrangedSubview(group(title, [row(label("Access"), text, button("Open System Settings") { [weak self] in self?.permissions.openSystemPreferences(for: kind) })], footer: [detail(kind == "microphone" ? "Required to record your voice. Audio stays on your Mac." : "Required for global recording shortcuts. Status refreshes when you return to Parrot.")]))
        }
        return stack
    }
    private func vertical(spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing; return stack
    }
    private func row(_ views: NSView...) -> NSStackView {
        let stack = NSStackView(); stack.alignment = .centerY; stack.spacing = 10
        stack.distribution = .fill
        for (index, view) in views.enumerated() {
            stack.addArrangedSubview(view)
            if index == 0 && views.count > 1 {
                let spacer = NSView()
                spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
                spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
                stack.addArrangedSubview(spacer)
            }
        }
        stack.widthAnchor.constraint(equalToConstant: width).isActive = true
        stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 26).isActive = true
        return stack
    }
    private func showMessage(_ text: String, in field: NSTextField) {
        field.stringValue = text; field.isHidden = text.isEmpty
        // Collapse a footer whose only notes are empty messages.
        if let notes = field.superview as? NSStackView { notes.isHidden = notes.arrangedSubviews.allSatisfy(\.isHidden) }
    }
    private func page() -> NSStackView { vertical(spacing: 24) }
    // A bold heading, a rounded card of rows split by hairlines, then optional footnotes.
    private func group(_ title: String, _ rows: [NSView], footer: [NSView] = []) -> NSView {
        let section = vertical(spacing: 8)
        let heading = NSStackView(views: [label(title, weight: .semibold)])
        heading.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 0)
        section.addArrangedSubview(heading)
        let box = NSBox(); box.boxType = .custom; box.titlePosition = .noTitle
        box.fillColor = Self.cardColor; box.borderWidth = 0
        box.cornerRadius = 10; box.contentViewMargins = .zero
        let contents = vertical(spacing: 10)
        for (index, view) in rows.enumerated() {
            if index > 0 { contents.addArrangedSubview(divider()) }
            contents.addArrangedSubview(view)
        }
        contents.translatesAutoresizingMaskIntoConstraints = false
        let interior = box.contentView!; interior.addSubview(contents)
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: width + 28),
            contents.widthAnchor.constraint(equalToConstant: width),
            contents.leadingAnchor.constraint(equalTo: interior.leadingAnchor, constant: 14),
            contents.trailingAnchor.constraint(equalTo: interior.trailingAnchor, constant: -14),
            contents.topAnchor.constraint(equalTo: interior.topAnchor, constant: 10),
            contents.bottomAnchor.constraint(equalTo: interior.bottomAnchor, constant: -10)
        ])
        section.addArrangedSubview(box)
        if !footer.isEmpty {
            let notes = vertical(spacing: 4)
            notes.edgeInsets = NSEdgeInsets(top: 2, left: 10, bottom: 0, right: 10)
            footer.forEach { notes.addArrangedSubview($0) }
            section.addArrangedSubview(notes)
        }
        return section
    }
    private func divider() -> NSView {
        let line = NSBox(); line.boxType = .separator
        line.widthAnchor.constraint(equalToConstant: width).isActive = true
        return line
    }
    private func symbol(_ name: String, size: CGFloat) -> NSImageView {
        let view = NSImageView(image: NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage())
        view.symbolConfiguration = .init(pointSize: size, weight: .medium)
        view.contentTintColor = .controlAccentColor
        view.setAccessibilityElement(false)
        return view
    }
    private func valueLabel(_ field: NSTextField) {
        field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular); field.textColor = .secondaryLabelColor
        field.alignment = .right; field.widthAnchor.constraint(equalToConstant: 48).isActive = true
    }
    private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text); label.font = .systemFont(ofSize: size, weight: weight); return label
    }
    private func detail(_ text: String) -> NSTextField { let label = NSTextField(wrappingLabelWithString: text); styleDetail(label); return label }
    private func styleDetail(_ label: NSTextField) { label.font = .systemFont(ofSize: 12); label.textColor = .secondaryLabelColor; label.preferredMaxLayoutWidth = width + 8 }

}

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); translatesAutoresizingMaskIntoConstraints = false }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
private final class SettingsButton: NSButton {
    var pressed: (() -> Void)?
    override init(frame: NSRect) { super.init(frame: frame); target = self; action = #selector(invoke) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { pressed?() }
}
private final class SettingsSwitch: NSSwitch {
    var changed: ((Bool) -> Void)?
    override init(frame: NSRect) { super.init(frame: frame); target = self; action = #selector(invoke) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { changed?(state == .on) }
}
private final class SettingsSlider: NSSlider {
    var changed: ((Double) -> Void)?
    override init(frame: NSRect) { super.init(frame: frame); target = self; action = #selector(invoke) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { changed?(doubleValue) }
}
private final class SettingsPopup: NSPopUpButton {
    var changed: ((Int) -> Void)?
    override init(frame: NSRect, pullsDown: Bool) { super.init(frame: frame, pullsDown: pullsDown); target = self; action = #selector(invoke) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { changed?(indexOfSelectedItem) }
}
