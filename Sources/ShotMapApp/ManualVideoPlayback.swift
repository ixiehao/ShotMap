@preconcurrency import AVFoundation
import Combine
import Foundation

/// Owns the editor's transport and observation lifetime. Time callbacks are
/// bounded to 10 Hz; exact frame extraction happens only after pausing/seeking.
@MainActor
final class ManualVideoPlayback: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime = 0.0
    @Published private(set) var endCount = 0
    private var observations: ManualPlaybackObservations?
    private var observationID = UUID()
    private var transportID = UUID()
    private var isSeeking = false
    private var expectedDuration = 0.0

    var hasObservers: Bool { observations != nil }

    func prepare(url: URL) {
        stopAndRelease()
        player.actionAtItemEnd = .pause
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        let id = UUID()
        observationID = id
        observations = ManualPlaybackObservations(player: player) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.observationID == id, self.isPlaying, !self.isSeeking else { return }
                // Read the current clock: a callback queued before a seek must
                // not restore its old event timestamp after the seek finishes.
                self.currentTime = self.finitePlayerTime()
            }
        } didEnd: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.observationID == id, self.isPlaying, !self.isSeeking else { return }
                let time = self.finitePlayerTime()
                guard self.expectedDuration > 0, time >= self.expectedDuration - 0.1 else { return }
                self.currentTime = time
                self.isPlaying = false
                self.endCount += 1
            }
        }
    }

    @discardableResult
    func play(from time: Double, duration: Double) -> Double {
        let upperBound = duration.isFinite ? max(0, duration) : 0
        expectedDuration = upperBound
        let position = time.isFinite ? min(max(0, time), upperBound) : 0
        // Clicking Play at the end should replay the video, not stay paused.
        let start = position >= max(0, upperBound - 0.001) ? 0 : position
        player.pause()
        currentTime = start
        isPlaying = true
        requestSeek(to: start, tolerance: 0, resumeAfterSeek: true)
        return start
    }

    @discardableResult
    func pause() -> Double {
        let position = isSeeking ? currentTime : finitePlayerTime()
        transportID = UUID()
        isSeeking = false
        player.pause()
        player.currentItem?.cancelPendingSeeks()
        isPlaying = false
        currentTime = position
        return currentTime
    }

    func seek(to time: Double, tolerance: Double = 0) {
        player.pause()
        isPlaying = false
        currentTime = time.isFinite ? max(0, time) : 0
        requestSeek(to: currentTime, tolerance: tolerance, resumeAfterSeek: false)
    }

    private func requestSeek(to time: Double, tolerance: Double, resumeAfterSeek: Bool) {
        let id = UUID()
        transportID = id
        isSeeking = true
        player.currentItem?.cancelPendingSeeks()
        let safeTolerance = tolerance.isFinite ? max(0, tolerance) : 0
        let toleranceTime = CMTime(seconds: safeTolerance, preferredTimescale: 60_000)
        player.seek(to: CMTime(seconds: time, preferredTimescale: 60_000),
                    toleranceBefore: toleranceTime, toleranceAfter: toleranceTime) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self, self.transportID == id else { return }
                self.isSeeking = false
                if resumeAfterSeek, self.isPlaying {
                    if finished { self.player.play() } else { self.isPlaying = false }
                }
            }
        }
    }

    func stopAndRelease() {
        observationID = UUID()
        transportID = UUID()
        isSeeking = false
        expectedDuration = 0
        isPlaying = false
        player.pause()
        player.cancelPendingPrerolls()
        player.currentItem?.cancelPendingSeeks()
        observations?.invalidate()
        observations = nil
        player.replaceCurrentItem(with: nil)
        currentTime = 0
    }

    private func finitePlayerTime() -> Double {
        let time = player.currentTime().seconds
        return time.isFinite ? max(0, time) : currentTime
    }
}

/// AVFoundation observation tokens must be removed from the player that
/// created them. This owner also cleans up if the hosted view is released
/// without a final onDisappear callback.
private final class ManualPlaybackObservations: @unchecked Sendable {
    private let player: AVPlayer
    private let lock = NSLock()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var invalidated = false

    init(player: AVPlayer, didAdvance: @escaping @Sendable (Double) -> Void,
         didEnd: @escaping @Sendable () -> Void) {
        self.player = player
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main
        ) { time in didAdvance(time.seconds) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
        ) { _ in didEnd() }
    }

    func invalidate() {
        let tokens = lock.withLock { () -> (Any?, NSObjectProtocol?)? in
            guard !invalidated else { return nil }
            invalidated = true
            let tokens = (timeObserver, endObserver)
            timeObserver = nil
            endObserver = nil
            return tokens
        }
        guard let tokens else { return }
        if let timeObserver = tokens.0 { player.removeTimeObserver(timeObserver) }
        if let endObserver = tokens.1 { NotificationCenter.default.removeObserver(endObserver) }
        player.pause()
        player.cancelPendingPrerolls()
        player.currentItem?.cancelPendingSeeks()
        player.replaceCurrentItem(with: nil)
    }

    deinit { invalidate() }
}
