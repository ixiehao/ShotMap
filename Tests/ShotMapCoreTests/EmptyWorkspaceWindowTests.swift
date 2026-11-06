import AppKit
import SwiftUI
import XCTest
@testable import ShotMapApp

final class EmptyWorkspaceWindowTests: XCTestCase {
    @MainActor
    func testPausedBatchShowsCompletedCanvasWithoutResizingAndResumeRestoresLivePreview() async throws {
        let fixture = try EmptyWorkspaceWindowFixture()
        defer { fixture.model.cancelGeneration(); fixture.close() }
        try await fixture.addCompletedPreview(size: CGSize(width: 160, height: 90))
        try await waitUntil { fixture.canvas != nil && !fixture.hasDefaultSize }
        let completedImage = try XCTUnwrap(fixture.model.previewImage)
        let completedFrame = fixture.window.frame
        let failedSources = (0..<16).map { fixture.directory.appendingPathComponent("missing-\($0).mp4") }
        fixture.model.addVideos(failedSources)
        for index in 1...failedSources.count {
            fixture.model.markJobFailed(index: index, message: "retry fixture")
        }

        fixture.model.retryFailedJobs()
        fixture.model.requestPause()
        try await waitUntil { fixture.model.isPaused || !fixture.model.isProcessing }
        XCTAssertTrue(fixture.model.isPaused, "Pause must stop at the next between-video checkpoint")
        XCTAssertFalse(fixture.model.showsProgressivePreview)
        XCTAssertTrue(fixture.model.previewImage === completedImage)
        try await waitUntil { fixture.canvas != nil }
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(fixture.window.frame, completedFrame, "Showing the completed image while paused must not resize the working window")

        fixture.model.resumeGeneration()
        XCTAssertTrue(fixture.model.isProcessing)
        XCTAssertFalse(fixture.model.isPaused)
        XCTAssertTrue(fixture.model.showsProgressivePreview)
        try await waitUntil { !fixture.model.isProcessing }
        XCTAssertFalse(fixture.model.showsProgressivePreview)
        XCTAssertNotNil(fixture.model.previewImage)
    }

    @MainActor
    func testClearingCompletedLandscapeAndPortraitRestoresDefaultSizeAndKeepsExports() async throws {
        let fixture = try EmptyWorkspaceWindowFixture()
        defer { fixture.close() }
        try await waitUntil { fixture.probe != nil }

        for size in [CGSize(width: 160, height: 90), CGSize(width: 90, height: 160)] {
            try await fixture.addCompletedPreview(size: size)
            try await waitUntil { !fixture.hasDefaultSize }
            let savedURL = try XCTUnwrap(fixture.model.lastSavedURL)
            XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL.path))

            fixture.model.clearVideos()

            try await waitUntil { fixture.hasDefaultSize }
            XCTAssertTrue(fixture.model.videoJobs.isEmpty)
            XCTAssertNil(fixture.model.previewImage)
            XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL.path), "Clearing the queue must keep exported files")
        }
    }

    @MainActor
    func testClearingAnUnprocessedQueueRestoresBothAxesWithoutResettingSettings() async throws {
        let fixture = try EmptyWorkspaceWindowFixture()
        defer { fixture.close() }
        try await waitUntil { fixture.probe != nil }
        fixture.model.addVideos([fixture.directory.appendingPathComponent("unprocessed.mp4")])
        fixture.model.width = 2_560
        fixture.model.showTimestamps = false
        fixture.window.setContentSize(NSSize(width: 1_100, height: 760))
        XCTAssertFalse(fixture.hasDefaultSize)

        fixture.model.clearVideos()

        try await waitUntil { fixture.hasDefaultSize }
        XCTAssertEqual(fixture.model.width, 2_560)
        XCTAssertFalse(fixture.model.showTimestamps)
    }

    @MainActor
    func testClearCancelsPendingResultFitAndNextResultStillExpands() async throws {
        let fixture = try EmptyWorkspaceWindowFixture()
        defer { fixture.close() }
        try await waitUntil { fixture.probe != nil }
        let probe = try XCTUnwrap(fixture.probe)
        fixture.window.setContentSize(NSSize(width: 1_100, height: 760))

        // Submit a result fit, then clear before its delayed work can run.
        probe.request = PreviewWindowAutoFitRequest(
            sourceID: "about-to-clear", aspectRatio: 16.0 / 9.0, layoutAspect: .source,
            panels: PreviewWindowPanelConfiguration(queueVisible: true, inspectorVisible: true)
        )
        probe.isEnabled = true
        probe.reportMeasurement()
        fixture.model.clearVideos()

        try await waitUntil { fixture.hasDefaultSize }
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertTrue(fixture.hasDefaultSize, "A stale result fit must not expand the cleared window again")

        try await fixture.addCompletedPreview(size: CGSize(width: 160, height: 90))
        try await waitUntil { !fixture.hasDefaultSize }
        XCTAssertGreaterThan(fixture.window.frame.width, fixture.defaultFrameSize.width)
    }

    @MainActor
    func testDefaultRestoreWaitsForFullScreenTransitionAndDoesNotRepeatOnEmptyLayout() async throws {
        let fixture = try EmptyWorkspaceWindowFixture()
        defer { fixture.close() }
        try await waitUntil { fixture.probe != nil }
        fixture.window.setContentSize(NSSize(width: 1_100, height: 760))
        let expanded = fixture.window.frame
        NotificationCenter.default.post(name: NSWindow.willEnterFullScreenNotification, object: fixture.window)

        fixture.model.clearVideos()
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(fixture.window.frame, expanded)
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: fixture.window)
        try await waitUntil { fixture.hasDefaultSize }

        // Resizing an empty workspace later is still a user choice.
        fixture.window.setContentSize(NSSize(width: 1_100, height: 760))
        let manuallyResized = fixture.window.frame
        fixture.probe?.reportMeasurement()
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(fixture.window.frame, manuallyResized)
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }
}

@MainActor
private final class EmptyWorkspaceWindowFixture {
    let model = StoryboardViewModel()
    let directory: URL
    let window: NSWindow
    private let session: URLSession

    init() throws {
        _ = NSApplication.shared
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ShotMap-window-reset-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WindowResetOfflineProtocol.self]
        session = URLSession(configuration: configuration)
        let checker = UpdateChecker(session: session)
        window = NSWindow(
            contentRect: CGRect(origin: .zero, size: MainWindowStartupLayout.contentSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView(model: model).environmentObject(checker))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    var probe: PreviewWindowMeasurementView? {
        func find(in view: NSView) -> PreviewWindowMeasurementView? {
            if let probe = view as? PreviewWindowMeasurementView { return probe }
            for child in view.subviews {
                if let probe = find(in: child) { return probe }
            }
            return nil
        }
        return window.contentView.flatMap { find(in: $0) }
    }

    var canvas: StoryboardCanvasScrollView? {
        func find(in view: NSView) -> StoryboardCanvasScrollView? {
            if let canvas = view as? StoryboardCanvasScrollView { return canvas }
            return view.subviews.lazy.compactMap { find(in: $0) }.first
        }
        return window.contentView.flatMap { find(in: $0) }
    }

    var defaultFrameSize: CGSize {
        let size = window.frameRect(forContentRect: CGRect(origin: .zero, size: MainWindowStartupLayout.contentSize)).size
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame.size ?? size
        return CGSize(width: min(size.width, visible.width), height: min(size.height, visible.height))
    }

    var hasDefaultSize: Bool {
        abs(window.frame.width - defaultFrameSize.width) < 1
            && abs(window.frame.height - defaultFrameSize.height) < 1
    }

    func addCompletedPreview(size: CGSize) async throws {
        let source = directory.appendingPathComponent("clip-\(UUID().uuidString).mp4")
        model.addVideos([source])
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        bitmap.bitmapData?.initialize(repeating: 128, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let result = StoryboardResult(frames: [CapturedFrame(id: 0, time: 1, jpegData: data)], sourceURL: source, duration: 2)
        let settings = ExportSettings(gridSide: 3, format: .png, width: 1_920)
        let completed = await model.completeJob(data: data, result: result, settings: settings, index: 0, total: 1)
        XCTAssertTrue(completed)
        XCTAssertNotNil(model.previewImage)
    }

    func close() {
        window.close()
        window.contentView = nil
        session.invalidateAndCancel()
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class WindowResetOfflineProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() { }
}
