import Foundation

actor StoreWriter {
    private let path: URL
    private let metrics: Metrics
    private let debounce: Duration

    private var pending: StoredState?
    private var pendingGeneration = 0
    private var timer: Task<Void, Never>?
    private let written = WrittenState()

    init(path: URL, metrics: Metrics, debounce: Duration) {
        self.path = path
        self.metrics = metrics
        self.debounce = debounce
    }

    nonisolated func assumeOnDisk(_ state: StoredState) {
        written.record(state, generation: 0)
    }

    func schedule(_ state: StoredState, generation: Int) {
        guard generation > pendingGeneration else { return }
        pendingGeneration = generation
        pending = state
        guard timer == nil else { return }
        timer = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            await self.flush()
        }
    }

    func flush() {
        timer?.cancel()
        timer = nil
        guard let state = pending else { return }
        pending = nil
        write(state, generation: pendingGeneration)
    }

    nonisolated func writeNow(_ state: StoredState, generation: Int) {
        write(state, generation: generation)
    }

    private nonisolated func write(_ state: StoredState, generation: Int) {
        written.writeIfNewer(state, generation: generation) {
            let wrote = metrics.measure(.storeWrite) {
                (try? JSONEncoder().encode(state).write(to: path, options: .atomic)) != nil
            }
            guard wrote else { return }
            metrics.count(.storeWrites)
            if pthread_main_np() != 0 { metrics.count(.storeWritesOnMain) }
        }
    }
}

private final class WrittenState: @unchecked Sendable {
    private let lock = NSLock()
    private var state: StoredState?
    private var generation = -1

    func record(_ s: StoredState, generation g: Int) {
        lock.withLock {
            state = s
            generation = g
        }
    }

    func writeIfNewer(_ s: StoredState, generation g: Int, _ write: () -> Void) {
        lock.withLock {
            guard g > generation else { return }
            generation = g
            guard s != state else { return }
            write()
            state = s
        }
    }
}
