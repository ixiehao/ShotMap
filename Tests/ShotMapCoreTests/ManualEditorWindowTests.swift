import AppKit
import SwiftUI
import XCTest
@testable import ShotMapApp

final class ManualEditorWindowTests: XCTestCase {
    @MainActor
    func testFirstPresentationPreservesRequestAndHostedContent() throws {
        let fixture = EditorWindowFixture()
        defer { fixture.dismiss() }
        let request = fixture.newRequest()
        fixture.request = request
        fixture.update()

        XCTAssertEqual(fixture.request?.id, request.id)
        XCTAssertEqual(fixture.presentedWindows.count, 1)
        XCTAssertNotNil(try XCTUnwrap(fixture.presentedWindows.first).contentView)
    }

    @MainActor
    func testSameRequestUpdatesAppearanceWithoutRecreatingWindow() throws {
        let fixture = EditorWindowFixture()
        defer { fixture.dismiss() }
        let request = fixture.newRequest()
        fixture.request = request
        fixture.update()
        let originalWindow = try XCTUnwrap(fixture.presentedWindows.first)
        let originalContent = originalWindow.contentView

        fixture.update(language: .english, colorScheme: .dark)

        XCTAssertEqual(fixture.request?.id, request.id)
        XCTAssertEqual(fixture.presentedWindows.count, 1)
        XCTAssertTrue(originalWindow.contentView === originalContent)
        XCTAssertEqual(originalWindow.title, AppLanguage.english.text("editor.title"))
        XCTAssertEqual(originalWindow.appearance?.name, .darkAqua)
    }

    @MainActor
    func testNativeWindowCloseDismissesRequestAndReleasesContent() throws {
        let fixture = EditorWindowFixture()
        defer { fixture.dismiss() }
        fixture.request = fixture.newRequest()
        fixture.update()
        let window = try XCTUnwrap(fixture.presentedWindows.first)

        window.close()

        XCTAssertNil(fixture.request)
        XCTAssertNil(window.contentView)
        fixture.update()
        XCTAssertEqual(fixture.presentedWindows.count, 1)
    }

    @MainActor
    func testReplacingRequestDoesNotDismissReplacement() throws {
        let fixture = EditorWindowFixture()
        defer { fixture.dismiss() }
        fixture.request = fixture.newRequest()
        fixture.update()
        let originalWindow = try XCTUnwrap(fixture.presentedWindows.first)
        let replacement = fixture.newRequest()

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
    func testClearingRequestAndDismantlingReleaseHostedWindow() throws {
        let fixture = EditorWindowFixture()
        defer { fixture.dismiss() }
        fixture.request = fixture.newRequest()
        fixture.update()
        let firstWindow = try XCTUnwrap(fixture.presentedWindows.first)
        fixture.request = nil
        fixture.update()
        XCTAssertNil(firstWindow.contentView)

        fixture.request = fixture.newRequest()
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
    let model = StoryboardViewModel()
    lazy var host = ManualFrameEditorWindowPresenter.HostView(presentWindow: { [weak self] window in
        self?.presentedWindows.append(window)
    })

    init() {
        _ = NSApplication.shared
    }

    func newRequest() -> ManualFrameEditorRequest {
        ManualFrameEditorRequest(
            previewID: UUID(),
            sourceURL: URL(fileURLWithPath: "/tmp/shotmap-window-lifecycle-test.mp4"),
            selectionLimit: 9,
            duration: 60,
            outputWidth: 1920
        )
    }

    func update(language: AppLanguage = .chinese, colorScheme: ColorScheme = .light) {
        host.update(
            request: Binding(get: { [weak self] in self?.request }, set: { [weak self] in self?.request = $0 }),
            model: model,
            language: language,
            colorScheme: colorScheme,
            onApply: { _, _ in }
        )
    }

    func dismiss() {
        ManualFrameEditorWindowPresenter.dismantleNSView(host, coordinator: ())
    }
}
