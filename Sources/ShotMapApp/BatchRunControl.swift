import Foundation

/// Coordinates a long-running batch without blocking its worker thread.
/// A requested pause takes effect at the next safe checkpoint (between videos),
/// so a partially rendered storyboard is never left behind.
actor BatchRunControl {
    private var pauseRequested = false
    private var resumeWaiters: [CheckedContinuation<Void, Never>] = []

    func requestPause() {
        pauseRequested = true
    }

    func isPauseRequested() -> Bool {
        pauseRequested
    }

    func waitUntilResumed() async {
        guard pauseRequested else { return }
        await withTaskCancellationHandler {
            guard !Task.isCancelled else { return }
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled, pauseRequested else {
                    continuation.resume()
                    return
                }
                resumeWaiters.append(continuation)
            }
        } onCancel: {
            // Cancellation must release a paused worker even if the view/model
            // has already gone away and cannot send an explicit resume call.
            Task { await self.resume() }
        }
    }

    func resume() {
        pauseRequested = false
        let waiters = resumeWaiters
        resumeWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
