import AppKit
import SwiftUI
import XCTest
@testable import ShotMapApp

final class PreviewWindowProbeReplacementTests: XCTestCase {
    @MainActor
    func testReplacingMeasurementViewDuringClearDoesNotStrandDefaultResize() async throws {
        let fixture = ProbeReplacementFixture()
        defer { fixture.close() }
        let first = fixture.attachProbe(resetID: UUID())
        fixture.expand()
        first.queueResetID = UUID()
        first.reportMeasurement()

        // SwiftUI can mount the next branch's background before dismantling
        // its predecessor during cancel -> completed image -> empty canvas.
        let replacement = fixture.attachProbe(resetID: first.queueResetID)
        PreviewWindowAutoFitProbe.dismantleNSView(first, coordinator: ())
        first.removeFromSuperview()
        replacement.reportMeasurement()

        try await waitForDefaultSize(fixture)
        replacement.reportMeasurement()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(fixture.window.frame.size, fixture.defaultSize)
    }

    @MainActor
    func testDetachedOldMeasurementCannotOverwriteCurrentProbeOrCancelItsClear() async throws {
        let fixture = ProbeReplacementFixture()
        defer { fixture.close() }
        let oldResetID = UUID()
        let obsolete = fixture.attachProbe(resetID: oldResetID)
        obsolete.fitter = nil
        obsolete.removeFromSuperview()
        let current = fixture.attachProbe(resetID: oldResetID)
        fixture.expand()
        current.queueResetID = UUID()
        current.reportMeasurement()

        // Native move/layout callbacks can arrive while the old view is no
        // longer attached. They carry stale state and must not take ownership.
        obsolete.fitter = fixture.fitter
        obsolete.request = PreviewWindowAutoFitRequest(sourceID: "obsolete-result", aspectRatio: 16.0 / 9,
            layoutAspect: .source, panels: .init(queueVisible: true, inspectorVisible: true))
        obsolete.reportMeasurement()

        try await waitForDefaultSize(fixture)
    }

    @MainActor
    private func waitForDefaultSize(_ fixture: ProbeReplacementFixture,
                                    file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while fixture.window.frame.size != fixture.defaultSize, ContinuousClock.now < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(fixture.window.frame.size, fixture.defaultSize, file: file, line: line)
    }
}

@MainActor
private final class ProbeReplacementFixture {
    let window: NSWindow
    let root: NSView
    let fitter = PreviewWindowAutoFitter()

    init() {
        _ = NSApplication.shared
        window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 100, y: 100), size: MainWindowStartupLayout.contentSize),
                          styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        root = NSView(frame: CGRect(origin: .zero, size: MainWindowStartupLayout.contentSize))
        window.contentView = root
    }

    var defaultSize: CGSize {
        let size = window.frameRect(forContentRect: CGRect(origin: .zero, size: MainWindowStartupLayout.contentSize)).size
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame.size ?? size
        return CGSize(width: min(size.width, visible.width), height: min(size.height, visible.height))
    }

    func expand() { window.setContentSize(CGSize(width: 1_280, height: 515)) }

    func attachProbe(resetID: UUID) -> PreviewWindowMeasurementView {
        let probe = PreviewWindowMeasurementView(frame: root.bounds)
        probe.queueResetID = resetID
        probe.fitter = fitter
        probe.isEnabled = true
        root.addSubview(probe)
        probe.reportMeasurement()
        return probe
    }

    func close() {
        for probe in root.subviews.compactMap({ $0 as? PreviewWindowMeasurementView }) {
            PreviewWindowAutoFitProbe.dismantleNSView(probe, coordinator: ())
        }
        window.close()
        window.contentView = nil
    }
}
