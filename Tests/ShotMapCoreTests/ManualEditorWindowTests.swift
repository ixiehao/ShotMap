import AppKit
import CoreGraphics
import SwiftUI
import XCTest
@testable import ShotMapApp

final class ManualEditorWindowTests: XCTestCase {
    @MainActor
    func testFirstPresentationPreservesRequestAndHostedContent() async throws {
        let fixture = EditorWindowFixture()
        defer { fixture.dismiss() }
        let request = try await fixture.newRequest()
        fixture.request = request
        fixture.update()

        XCTAssertEqual(fixture.request?.id, request.id)
        XCTAssertEqual(fixture.presentedWindows.count, 1)
        XCTAssertNotNil(try XCTUnwrap(fixture.presentedWindows.first).contentView)
    }

    @MainActor
    func testSameRequestUpdatesAppearanceWithoutRecreatingWindow() async throws {
        let fixture = EditorWindowFixture()
        defer { fixture.dismiss() }
        let request = try await fixture.newRequest()
        fixture.request = request
        fixture.update()
        let originalWindow = try XCTUnwrap(fixture.presentedWindows.first)
        let originalContent = originalWindow.contentView

        fixture.update(language: .english, colorScheme: .dark)

        XCTAssertEqual(fixture.request?.id, request.id)
        XCTAssertEqual(fixture.presentedWindows.count, 1)
        XCTAssertTrue(originalWindow.contentView === originalContent)
        XCTAssertEqual(originalWindow.title, request.sourceURL.lastPathComponent)
        XCTAssertEqual(originalWindow.appearance?.name, .darkAqua)
    }

    @MainActor
    func testNativeWindowCloseDismissesRequestAndReleasesContent() async throws {
        let fixture = EditorWindowFixture()
        defer { fixture.dismiss() }
        fixture.request = try await fixture.newRequest()
        fixture.update()
        let window = try XCTUnwrap(fixture.presentedWindows.first)

        window.close()

        XCTAssertNil(fixture.request)
        XCTAssertNil(window.contentView)
        fixture.update()
        XCTAssertEqual(fixture.presentedWindows.count, 1)
    }

    @MainActor
    func testReplacingRequestDoesNotDismissReplacement() async throws {
        let fixture = EditorWindowFixture()
        defer { fixture.dismiss() }
        fixture.request = try await fixture.newRequest()
        fixture.update()
        let originalWindow = try XCTUnwrap(fixture.presentedWindows.first)
        let replacement = try await fixture.newRequest()

        fixture.request = replacement
        fixture.update()

        XCTAssertEqual(fixture.request?.id, replacement.id)
        XCTAssertEqual(fixture.presentedWindows.count, 2)
        XCTAssertNil(originalWindow.contentView)
        let replacementWindow = try XCTUnwrap(fixture.presentedWindows.last)
        XCTAssertFalse(replacementWindow === originalWindow)
        XCTAssertNotNil(replacementWindow.contentView)

        // A delayed delegate notification from the old window cannot revoke
        // the new SwiftUI request or release the replacement's hosted tree.
        fixture.host.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: originalWindow))
        XCTAssertEqual(fixture.request?.id, replacement.id)
        XCTAssertNotNil(replacementWindow.contentView)
    }

    @MainActor
    func testClearingQueueClosesAnEditorWhosePreviewNoLongerExists() async throws {
        let fixture = EditorWindowFixture()
        defer { fixture.dismiss() }
        fixture.request = try await fixture.newRequest()
        fixture.update()
        let window = try XCTUnwrap(fixture.presentedWindows.first)

        fixture.model.clearVideos()
        fixture.update()
        XCTAssertNil(window.contentView, "An invalidated editor must release its pending decoder work")
        for _ in 0..<5 { await Task.yield() }
        XCTAssertNil(fixture.request)
        XCTAssertTrue(fixture.model.completedPreviews.isEmpty)
    }

    @MainActor
    func testNewGenerationInvalidatesOldEditorButRetryKeepsValidTarget() async throws {
        let fixture = EditorWindowFixture()
        defer { fixture.dismiss() }
        let request = try await fixture.newRequest()
        fixture.request = request
        fixture.update()
        let window = try XCTUnwrap(fixture.presentedWindows.first)
        let content = window.contentView

        // A retry processes another job but retains history. It must not throw
        // away this valid editing session or recreate its content tree.
        fixture.model.isProcessing = true
        fixture.update()
        XCTAssertEqual(fixture.request?.id, request.id)
        XCTAssertTrue(window.contentView === content)
        fixture.model.isProcessing = false

        fixture.model.addVideos([request.sourceURL])
        fixture.model.generate()
        fixture.update()
        XCTAssertNil(window.contentView)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertNil(fixture.request)
        fixture.model.cancelGeneration()
    }

    @MainActor
    func testDeferredInvalidationCannotDismissANewerRequest() async throws {
        let fixture = EditorWindowFixture()
        defer { fixture.dismiss() }
        let invalid = try await fixture.newRequest()
        let replacement = try await fixture.newRequest()
        fixture.request = invalid
        fixture.update()
        fixture.model.clearVideos()
        fixture.update()
        // The dismissal is deliberately deferred beyond HostView.update.
        // A newer request arriving in that interval owns the binding now.
        fixture.request = replacement
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(fixture.request?.id, replacement.id)
    }

    @MainActor
    func testLateRefinementFromReplacedEditorCannotApplyOrCloseReplacement() async throws {
        let fixture = EditorWindowFixture()
        defer { fixture.dismiss() }
        fixture.request = try await fixture.newRequest()
        fixture.update()
        let oldWindow = try XCTUnwrap(fixture.presentedWindows.first)
        let oldHost = try XCTUnwrap(oldWindow.contentView as? NSHostingView<ManualFrameEditor>)
        let lateApply = oldHost.rootView.onApply
        let replacement = try await fixture.newRequest()
        fixture.request = replacement
        fixture.update()
        let replacementWindow = try XCTUnwrap(fixture.presentedWindows.last)

        lateApply([], ExportSettings(format: .jpeg))

        XCTAssertTrue(fixture.appliedPreviewIDs.isEmpty)
        XCTAssertEqual(fixture.request?.id, replacement.id)
        XCTAssertNotNil(replacementWindow.contentView)
    }

    @MainActor
    func testRefinementFinishingBeforeInvalidationUpdateCannotReportSuccess() async throws {
        let fixture = EditorWindowFixture()
        defer { fixture.dismiss() }
        fixture.request = try await fixture.newRequest()
        fixture.update()
        let window = try XCTUnwrap(fixture.presentedWindows.first)
        let host = try XCTUnwrap(window.contentView as? NSHostingView<ManualFrameEditor>)
        let lateApply = host.rootView.onApply
        fixture.model.clearVideos()

        // SwiftUI has not yet called HostView.update, so the final callback
        // must validate the target itself before invoking the model action.
        lateApply([], ExportSettings(format: .jpeg))

        XCTAssertTrue(fixture.appliedPreviewIDs.isEmpty)
        XCTAssertNil(fixture.request)
        XCTAssertNil(window.contentView)
        XCTAssertTrue(fixture.model.completedPreviews.isEmpty)
    }

    @MainActor
    func testClearingRequestAndDismantlingReleaseHostedWindow() async throws {
        let fixture = EditorWindowFixture()
        defer { fixture.dismiss() }
        fixture.request = try await fixture.newRequest()
        fixture.update()
        let firstWindow = try XCTUnwrap(fixture.presentedWindows.first)
        fixture.request = nil
        fixture.update()
        XCTAssertNil(firstWindow.contentView)

        fixture.request = try await fixture.newRequest()
        fixture.update()
        let secondWindow = try XCTUnwrap(fixture.presentedWindows.last)
        fixture.dismiss()
        XCTAssertNil(fixture.request)
        XCTAssertNil(secondWindow.contentView)
    }
}

@MainActor
private final class EditorWindowFixture {
    var request: ManualFrameEditorRequest?
    var presentedWindows: [NSWindow] = []
    var appliedPreviewIDs: [UUID] = []
    let model = StoryboardViewModel()
    lazy var host = ManualFrameEditorWindowPresenter.HostView(presentWindow: { [weak self] window in
        self?.presentedWindows.append(window)
    })

    init() {
        _ = NSApplication.shared
    }

    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ShotMap-window-lifecycle-\(UUID())")

    func newRequest() async throws -> ManualFrameEditorRequest {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("fixture-\(UUID()).mp4")
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 18, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 18))
        let data = try XCTUnwrap(ImageCodec.jpegData(from: XCTUnwrap(context.makeImage()), compressionQuality: 0.8))
        _ = await model.completeJob(data: data, result: StoryboardResult(frames: [], sourceURL: source, duration: 60),
                                    settings: ExportSettings(format: .jpeg), index: 0, total: 1)
        return ManualFrameEditorRequest(
            previewID: try XCTUnwrap(model.completedPreviews.last?.id), sourceURL: source, duration: 60
        )
    }

    func update(language: AppLanguage = .chinese, colorScheme: ColorScheme = .light) {
        host.update(
            request: Binding(get: { [weak self] in self?.request }, set: { [weak self] in self?.request = $0 }),
            model: model,
            language: language,
            colorScheme: colorScheme,
            onApply: { [weak self] request, _, _ in self?.appliedPreviewIDs.append(request.previewID) }
        )
    }

    func dismiss() {
        ManualFrameEditorWindowPresenter.dismantleNSView(host, coordinator: ())
        model.cancelGeneration()
        model.clearVideos()
        try? FileManager.default.removeItem(at: directory)
    }
}
