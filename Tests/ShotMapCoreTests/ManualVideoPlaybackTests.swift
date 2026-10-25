import AVFoundation
import XCTest
@testable import ShotMapApp

final class ManualVideoPlaybackTests: XCTestCase {
    @MainActor
    func testClosingOrReplacingPlaybackReleasesTheOldItemAndObservers() async throws {
        let playback = ManualVideoPlayback()
        playback.prepare(url: URL(fileURLWithPath: "/tmp/ShotMap-first-playback.mp4"))
        let oldItem = try XCTUnwrap(playback.player.currentItem)
        XCTAssertTrue(playback.hasObservers)
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: oldItem)
        playback.prepare(url: URL(fileURLWithPath: "/tmp/ShotMap-second-playback.mp4"))
        XCTAssertFalse(playback.player.currentItem === oldItem)
        XCTAssertTrue(playback.hasObservers)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(playback.endCount, 0, "An older item's queued end notification cannot stop the new session")
        playback.play(from: 1, duration: 3)
        playback.stopAndRelease()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(playback.isPlaying)
        XCTAssertFalse(playback.hasObservers)
        XCTAssertNil(playback.player.currentItem)
        XCTAssertEqual(playback.currentTime, 0)
        XCTAssertEqual(playback.player.rate, 0)
    }

    @MainActor
    func testReleasedPlaybackOwnerCannotLeaveItsPlayerRunningOrObserved() {
        var playback: ManualVideoPlayback? = ManualVideoPlayback()
        playback?.prepare(url: URL(fileURLWithPath: "/tmp/ShotMap-released-playback.mp4"))
        let player = playback?.player
        let weakOwner = WeakPlaybackOwner(playback)
        playback = nil
        XCTAssertNil(weakOwner.value)
        XCTAssertNil(player?.currentItem, "The observation owner also releases its media if onDisappear was skipped")
        XCTAssertEqual(player?.rate, 0)
    }

    @MainActor
    func testPlaybackRestartAndNonfiniteSeeksRemainBounded() {
        let playback = ManualVideoPlayback()
        defer { playback.stopAndRelease() }
        XCTAssertEqual(playback.play(from: 10, duration: 10), 0)
        XCTAssertEqual(playback.play(from: -1, duration: 10), 0)
        XCTAssertEqual(playback.play(from: .nan, duration: 10), 0)
        playback.seek(to: .infinity, tolerance: .nan)
        XCTAssertEqual(playback.currentTime, 0)
        XCTAssertFalse(playback.isPlaying)
    }
}

private final class WeakPlaybackOwner {
    weak var value: ManualVideoPlayback?
    init(_ value: ManualVideoPlayback?) { self.value = value }
}
