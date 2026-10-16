import AppKit
import Combine
import Sparkle

/// Sparkle owns the update schedule and installer; no app-specific polling loop is needed.
@MainActor
final class UpdateController: NSObject, ObservableObject, @preconcurrency SPUStandardUserDriverDelegate {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var startupError: String?

    var willPresentUI: (() -> Void)?
    private var controller: SPUStandardUpdaterController?

    func start() {
        guard controller == nil else { return }
        do {
            try UpdateConfiguration.validate(Bundle.main.infoDictionary ?? [:])
            let controller = SPUStandardUpdaterController(
                startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self
            )
            try controller.updater.start()
            self.controller = controller
            controller.updater.publisher(for: \.canCheckForUpdates)
                .removeDuplicates()
                .receive(on: RunLoop.main)
                .assign(to: &$canCheckForUpdates)
            controller.updater.publisher(for: \.automaticallyChecksForUpdates)
                .removeDuplicates()
                .receive(on: RunLoop.main)
                .assign(to: &$automaticallyChecksForUpdates)
            startupError = nil
        } catch {
            // A malformed local build should not interrupt recording with an alert.
            startupError = error.localizedDescription
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        willPresentUI?()
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    func standardUserDriverWillShowModalAlert() { willPresentUI?() }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        if handleShowingUpdate { willPresentUI?() }
    }
}

