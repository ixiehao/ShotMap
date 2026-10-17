import AppKit
import SwiftUI

/// Presents manual frame selection as a normal, movable and resizable macOS
/// window. A sheet is attached to the parent window and cannot be repositioned;
/// this small AppKit bridge keeps the editor independent without changing its
/// SwiftUI content or selection workflow.
struct ManualFrameEditorWindowPresenter: NSViewRepresentable {
    @Binding var request: ManualFrameEditorRequest?
    @ObservedObject var model: StoryboardViewModel
    let language: AppLanguage
    let colorScheme: ColorScheme
    let onApply: (ManualFrameEditorRequest, [CapturedFrame]) -> Void

    func makeNSView(context: Context) -> HostView {
        HostView()
    }

    func updateNSView(_ nsView: HostView, context: Context) {
        nsView.update(
            request: $request,
            model: model,
            language: language,
            colorScheme: colorScheme,
            onApply: onApply
        )
    }

    static func dismantleNSView(_ nsView: HostView, coordinator: ()) {
        nsView.closeEditor()
    }

    final class HostView: NSView, NSWindowDelegate {
        private var currentRequestID: UUID?
        private var editorWindow: NSWindow?
        private var requestBinding: Binding<ManualFrameEditorRequest?>?
        private var editorConfiguration: ManualFrameEditorConfiguration?
        private var presentWindow: (NSWindow) -> Void = { window in
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = false
        }

        convenience init(presentWindow: @escaping (NSWindow) -> Void) {
            self.init(frame: .zero)
            self.presentWindow = presentWindow
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func update(
            request: Binding<ManualFrameEditorRequest?>,
            model: StoryboardViewModel,
            language: AppLanguage,
            colorScheme: ColorScheme,
            onApply: @escaping (ManualFrameEditorRequest, [CapturedFrame]) -> Void
        ) {
            requestBinding = request
            guard let requestValue = request.wrappedValue else {
                releaseEditorWindow()
                return
            }
            guard currentRequestID != requestValue.id || editorWindow == nil else {
                editorWindow?.appearance = Self.appKitAppearance(for: colorScheme)
                editorWindow?.title = language.text("editor.title")
                if editorConfiguration?.colorScheme != colorScheme {
                    editorConfiguration?.colorScheme = colorScheme
                }
                if editorConfiguration?.language != language {
                    editorConfiguration?.language = language
                }
                if editorWindow?.isMiniaturized == true {
                    editorWindow?.deminiaturize(nil)
                }
                return
            }

            // Replacing a hosted window releases its resources, but must not
            // dismiss the new request that SwiftUI has just supplied.
            releaseEditorWindow()
            currentRequestID = requestValue.id
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1_280, height: 800),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = language.text("editor.title")
            // This is a separate NSWindow, so it does not automatically inherit
            // ContentView's preferredColorScheme. Set its AppKit appearance as
            // well as the hosted SwiftUI preference to keep the entire editor—
            // title bar, surfaces and controls—in sync with Batch Studio.
            window.appearance = Self.appKitAppearance(for: colorScheme)
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.minSize = NSSize(width: 1_000, height: 680)
            window.contentMinSize = NSSize(width: 1_000, height: 680)
            window.maxSize = NSSize(width: 16_384, height: 16_384)
            // Keep a deliberately resized/repositioned editor where the person
            // left it.  Falling back to the centre only on a first launch also
            // prevents a manual editor from reopening partly off-screen.
            let autosaveName = "ShotMapManualFrameEditor"
            window.setFrameAutosaveName(autosaveName)
            if !window.setFrameUsingName(autosaveName) {
                window.center()
            }
            window.delegate = self
            let configuration = ManualFrameEditorConfiguration(
                colorScheme: colorScheme,
                language: language
            )
            editorConfiguration = configuration
            window.contentView = NSHostingView(
                rootView: ManualFrameEditor(
                    model: model,
                    sourceURL: requestValue.sourceURL,
                    selectionLimit: requestValue.selectionLimit,
                    duration: requestValue.duration,
                    outputWidth: requestValue.outputWidth,
                    configuration: configuration,
                    onClose: { [weak self] in self?.closeEditor() }
                ) { [weak self] frames in
                    onApply(requestValue, frames)
                    self?.closeEditor()
                }
            )
            editorWindow = window
            presentWindow(window)
        }

        private static func appKitAppearance(for colorScheme: ColorScheme) -> NSAppearance? {
            NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        }

        func windowWillClose(_ notification: Notification) {
            guard let window = notification.object as? NSWindow,
                  window === editorWindow else { return }
            let closedRequestID = currentRequestID
            currentRequestID = nil
            editorWindow = nil
            editorConfiguration = nil
            // Release the hosting tree now: onDisappear cancels its decoder
            // tasks even when AppKit retains the closed window temporarily.
            window.contentView = nil
            dismissRequest(ifMatching: closedRequestID)
        }

        fileprivate func closeEditor() {
            let closedRequestID = currentRequestID
            releaseEditorWindow()
            dismissRequest(ifMatching: closedRequestID)
        }

        private func dismissRequest(ifMatching requestID: UUID?) {
            guard let requestID, requestBinding?.wrappedValue?.id == requestID else { return }
            requestBinding?.wrappedValue = nil
        }

        private func releaseEditorWindow() {
            let window = editorWindow
            editorWindow = nil
            currentRequestID = nil
            editorConfiguration = nil
            window?.delegate = nil
            window?.close()
            window?.contentView = nil
        }
    }
}
