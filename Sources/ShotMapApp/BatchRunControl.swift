import Foundation

/// Coordinates a long-running batch without blocking its worker thread.
/// A requested pause takes effect at the next safe checkpoint (between videos),
/// so a partially rendered storyboard is never left behind.
actor BatchRunControl {
    private var pauseRequested = false
    private var resumeWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    var waitingWorkerCount: Int { resumeWaiters.count }

    func requestPause() {
        pauseRequested = true
    }

    func isPauseRequested() -> Bool {
        pauseRequested
    }

    func waitUntilResumed() async {
        guard pauseRequested else { return }
        let waiterID = UUID()
        await withTaskCancellationHandler {
            guard !Task.isCancelled else { return }
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled, pauseRequested else {
                    continuation.resume()
                    return
                }
                resumeWaiters[waiterID] = continuation
            }
        } onCancel: {
            // Cancellation must release a paused worker even if the view/model
            // has already gone away and cannot send an explicit resume call.
            Task { await self.cancelWaiter(waiterID) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        // Cancelling one worker must not resume a different worker or clear a
        // pause that was requested while the cancellation handler was queued.
        resumeWaiters.removeValue(forKey: id)?.resume()
    }

    func resume() {
        pauseRequested = false
        let waiters = resumeWaiters.values
        resumeWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
