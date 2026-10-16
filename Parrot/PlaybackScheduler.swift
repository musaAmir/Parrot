import Foundation

/// A new take or an explicit playback action supersedes any delayed playback.
final class PlaybackScheduler {
    private var pending: DispatchWorkItem?
    private var generation = UUID()

    func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
        cancel()
        let expected = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == expected else { return }
            self.pending = nil
            action()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: work)
    }

    func cancel() {
        generation = UUID()
        pending?.cancel()
        pending = nil
    }

    deinit { pending?.cancel() }
}
