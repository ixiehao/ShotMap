import AppKit
import SwiftUI

struct PreviewWindowPanelConfiguration: Equatable, Sendable {
    let queueVisible: Bool
    let inspectorVisible: Bool

    var minimumWindowWidth: CGFloat {
        if queueVisible && inspectorVisible { return 720 }
        return queueVisible || inspectorVisible ? 600 : 480
    }
}

struct PreviewWindowAutoFitRequest: Equatable, Sendable {
    let sourceID: String
    let aspectRatio: Double
    let layoutAspect: StoryboardAspect
    let panels: PreviewWindowPanelConfiguration

    var trigger: PreviewWindowAutoFitTrigger {
        PreviewWindowAutoFitTrigger(sourceID: sourceID, layoutAspect: layoutAspect, panels: panels)
    }
}

/// Resolution upgrades and theme changes deliberately do not create a trigger.
struct PreviewWindowAutoFitTrigger: Equatable {
    let sourceID: String
    let layoutAspect: StoryboardAspect
    let panels: PreviewWindowPanelConfiguration
}

enum PreviewWindowAutoFitGeometry {
    static func initialLandscapeWidth(currentWidth: CGFloat, startupWidth: CGFloat) -> CGFloat {
        // The compact empty window is not a manually chosen result size.
        // Keep a width adjusted before the first result, if it differs.
        abs(currentWidth - startupWidth) <= 1 ? 1_280 : currentWidth
    }

    /// `viewportSize` includes the canvas's edge padding. The measured difference
    /// from the native frame accounts for all sidebars, headers, safe areas and
    /// footers without assuming a particular title-bar height.
    static func fittedFrame(
        currentFrame: CGRect,
        viewportSize: CGSize,
        visibleFrame: CGRect,
        minimumSize: CGSize,
        aspectRatio: Double,
        preferredLandscapeWidth: CGFloat = 1_280,
        preferredPortraitHeight: CGFloat = 880,
        canvasInset: CGFloat = 12
    ) -> CGRect? {
        let values = [currentFrame.origin.x, currentFrame.origin.y, currentFrame.width,
                      currentFrame.height, viewportSize.width, viewportSize.height,
                      visibleFrame.origin.x, visibleFrame.origin.y, visibleFrame.width,
                      visibleFrame.height, minimumSize.width, minimumSize.height,
                      preferredLandscapeWidth, preferredPortraitHeight, canvasInset]
        guard values.allSatisfy(\.isFinite), aspectRatio.isFinite, aspectRatio > 0,
              currentFrame.width > 0, currentFrame.height > 0,
              viewportSize.width > 0, viewportSize.height > 0,
              visibleFrame.width > 0, visibleFrame.height > 0 else { return nil }

        let inset = max(0, canvasInset) * 2
        let chromeWidth = max(0, currentFrame.width - viewportSize.width)
        let chromeHeight = max(0, currentFrame.height - viewportSize.height)
        let imageLimit = CGSize(width: max(1, visibleFrame.width - chromeWidth - inset),
                               height: max(1, visibleFrame.height - chromeHeight - inset))
        let ratio = CGFloat(aspectRatio)
        let imageSize: CGSize
        if ratio >= 1 {
            let preferredImageWidth = max(1, min(preferredLandscapeWidth, visibleFrame.width) - chromeWidth - inset)
            let width = min(preferredImageWidth, imageLimit.width, imageLimit.height * ratio)
            imageSize = CGSize(width: width, height: width / ratio)
        } else {
            let preferredImageHeight = max(1, min(preferredPortraitHeight, visibleFrame.height) - chromeHeight - inset)
            let height = min(preferredImageHeight, imageLimit.height, imageLimit.width / ratio)
            imageSize = CGSize(width: height * ratio, height: height)
        }

        // A display smaller than the declared minimum takes precedence: the
        // entire frame must remain inside that display's actual visible area.
        let minimumWidth = min(visibleFrame.width, max(1, minimumSize.width))
        let minimumHeight = min(visibleFrame.height, max(1, minimumSize.height))
        let width = min(visibleFrame.width, max(minimumWidth, (imageSize.width + chromeWidth + inset).rounded(.up)))
        let height = min(visibleFrame.height, max(minimumHeight, (imageSize.height + chromeHeight + inset).rounded(.up)))
        let x = min(max(currentFrame.midX - width / 2, visibleFrame.minX), visibleFrame.maxX - width)
        let y = min(max(currentFrame.maxY - height, visibleFrame.minY), visibleFrame.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// One controller survives canvas/image replacement. It does not take over the
/// window delegate or fit in response to its own geometry changes.
@MainActor
final class PreviewWindowAutoFitter: NSObject, ObservableObject {
    private weak var probe: PreviewWindowMeasurementView?
    private weak var observedWindow: NSWindow?
    private var request: PreviewWindowAutoFitRequest?
    private var isEnabled = false
    private var lastHandledTrigger: PreviewWindowAutoFitTrigger?
    private var pendingFit: Task<Void, Never>?
    private var isTransitioningFullScreen = false
    private var preferredLandscapeWidth: CGFloat?
    private var preferredPortraitHeight: CGFloat = 880
    private var lastQueueResetID: UUID?
    private var needsDefaultSize = false

    fileprivate func receive(_ view: PreviewWindowMeasurementView,
                             request: PreviewWindowAutoFitRequest?, isEnabled: Bool, queueResetID: UUID) {
        // A detached predecessor can still report a native move/layout event.
        // It must not replace the currently attached view or its request.
        guard let window = view.window else { return }
        if probe !== view {
            // Delayed work captures its measuring view. SwiftUI can replace
            // that view while switching processing/result/empty branches;
            // otherwise an old default-size task can strand pendingFit when
            // its identity guard fails, blocking the replacement's resize.
            pendingFit?.cancel()
            pendingFit = nil
        }
        probe = view
        self.request = request
        self.isEnabled = isEnabled
        observe(window)
        if let lastQueueResetID, lastQueueResetID != queueResetID {
            pendingFit?.cancel()
            pendingFit = nil
            lastHandledTrigger = nil
            preferredLandscapeWidth = nil
            preferredPortraitHeight = 880
            needsDefaultSize = true
        }
        lastQueueResetID = queueResetID
        if needsDefaultSize {
            if request == nil {
                scheduleDefaultSize(view)
                return
            }
            // A new result supersedes a reset deferred during full screen.
            needsDefaultSize = false
        }
        guard let request else {
            pendingFit?.cancel()
            pendingFit = nil
            return
        }
        if preferredLandscapeWidth == nil {
            preferredLandscapeWidth = PreviewWindowAutoFitGeometry.initialLandscapeWidth(
                currentWidth: window.frame.width,
                startupWidth: min(MainWindowStartupLayout.contentSize.width,
                                  window.screen?.visibleFrame.width ?? MainWindowStartupLayout.contentSize.width)
            )
        }

        if window.inLiveResize {
            if request.aspectRatio >= 1 { preferredLandscapeWidth = window.frame.width }
            else { preferredPortraitHeight = window.frame.height }
            consumeWithoutResizing(request.trigger)
            return
        }
        guard isEnabled else {
            pendingFit?.cancel()
            pendingFit = nil
            return
        }
        guard request.trigger != lastHandledTrigger else { return }
        if window.styleMask.contains(.fullScreen) || isTransitioningFullScreen {
            consumeWithoutResizing(request.trigger)
            return
        }

        pendingFit?.cancel()
        pendingFit = Task { @MainActor [weak self, weak view] in
            do { try await Task.sleep(nanoseconds: 60_000_000) }
            catch { return }
            guard let self, let view else { return }
            self.fitIfReady(view)
        }
    }

    fileprivate func detach(_ view: PreviewWindowMeasurementView) {
        guard probe === view else { return }
        pendingFit?.cancel()
        pendingFit = nil
        probe = nil
    }

    private func fitIfReady(_ view: PreviewWindowMeasurementView) {
        guard probe === view, isEnabled, let request, request.trigger != lastHandledTrigger,
              let window = view.window, let screen = window.screen,
              view.bounds.width > 1, view.bounds.height > 1 else { return }
        guard !window.inLiveResize, !window.styleMask.contains(.fullScreen), !isTransitioningFullScreen else {
            consumeWithoutResizing(request.trigger)
            return
        }
        let nativeContentMinimum = window.frameRect(forContentRect: CGRect(origin: .zero, size: window.contentMinSize)).size
        let minimum = CGSize(width: max(request.panels.minimumWindowWidth, window.minSize.width, nativeContentMinimum.width),
                             height: max(480, window.minSize.height, nativeContentMinimum.height))
        guard let frame = PreviewWindowAutoFitGeometry.fittedFrame(
            currentFrame: window.frame,
            viewportSize: view.bounds.size,
            visibleFrame: screen.visibleFrame,
            minimumSize: minimum,
            aspectRatio: request.aspectRatio,
            preferredLandscapeWidth: preferredLandscapeWidth ?? 1_280,
            preferredPortraitHeight: preferredPortraitHeight
        ) else { return }

        lastHandledTrigger = request.trigger
        pendingFit = nil
        if abs(frame.width - window.frame.width) > 1 || abs(frame.height - window.frame.height) > 1
            || abs(frame.origin.x - window.frame.origin.x) > 1 || abs(frame.origin.y - window.frame.origin.y) > 1 {
            window.setFrame(frame, display: true, animate: false)
        }
    }

    private func scheduleDefaultSize(_ view: PreviewWindowMeasurementView) {
        guard pendingFit == nil else { return }
        pendingFit = Task { @MainActor [weak self, weak view] in
            do { try await Task.sleep(nanoseconds: 60_000_000) }
            catch { return }
            guard let self, let view, self.probe === view else { return }
            self.pendingFit = nil
            guard self.needsDefaultSize, self.request == nil,
                  let window = view.window,
                  !window.inLiveResize, !window.styleMask.contains(.fullScreen),
                  !self.isTransitioningFullScreen,
                  let screen = window.screen ?? NSScreen.main else { return }
            self.needsDefaultSize = false
            let desiredFrameSize = window.frameRect(forContentRect: CGRect(
                origin: .zero, size: MainWindowStartupLayout.contentSize
            )).size
            let frame = MainWindowStartupLayout.frame(
                currentFrame: window.frame, desiredFrameSize: desiredFrameSize,
                visibleFrame: screen.visibleFrame
            )
            window.setFrame(frame, display: true, animate: false)
        }
    }

    private func consumeWithoutResizing(_ trigger: PreviewWindowAutoFitTrigger) {
        pendingFit?.cancel()
        pendingFit = nil
        lastHandledTrigger = trigger
    }

    private func observe(_ window: NSWindow) {
        guard observedWindow !== window else { return }
        NotificationCenter.default.removeObserver(self)
        observedWindow = window
        isTransitioningFullScreen = false
        for name in [NSWindow.willEnterFullScreenNotification, NSWindow.willExitFullScreenNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(willTransitionFullScreen), name: name, object: window)
        }
        for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(didTransitionFullScreen), name: name, object: window)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(didEndLiveResize),
                                               name: NSWindow.didEndLiveResizeNotification, object: window)
    }

    @objc private func willTransitionFullScreen() {
        isTransitioningFullScreen = true
        pendingFit?.cancel()
        pendingFit = nil
    }

    @objc private func didTransitionFullScreen() {
        isTransitioningFullScreen = false
        resumeDefaultSizeIfNeeded()
    }

    @objc private func didEndLiveResize() { resumeDefaultSizeIfNeeded() }

    private func resumeDefaultSizeIfNeeded() {
        guard needsDefaultSize, let probe else { return }
        scheduleDefaultSize(probe)
    }
}

struct PreviewWindowAutoFitProbe: NSViewRepresentable {
    let fitter: PreviewWindowAutoFitter
    let request: PreviewWindowAutoFitRequest?
    let isEnabled: Bool
    let queueResetID: UUID

    func makeNSView(context: Context) -> PreviewWindowMeasurementView {
        PreviewWindowMeasurementView(frame: .zero)
    }

    func updateNSView(_ view: PreviewWindowMeasurementView, context: Context) {
        view.fitter = fitter
        view.request = request
        view.isEnabled = isEnabled
        view.queueResetID = queueResetID
        view.reportMeasurement()
    }

    static func dismantleNSView(_ view: PreviewWindowMeasurementView, coordinator: ()) {
        view.fitter?.detach(view)
        view.fitter = nil
    }
}

@MainActor
final class PreviewWindowMeasurementView: NSView {
    weak var fitter: PreviewWindowAutoFitter?
    var request: PreviewWindowAutoFitRequest?
    var isEnabled = false
    var queueResetID = UUID()

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportMeasurement()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        reportMeasurement()
    }

    override func layout() {
        super.layout()
        reportMeasurement()
    }

    // The measurement overlay never participates in image or keyboard input.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func reportMeasurement() {
        fitter?.receive(self, request: request, isEnabled: isEnabled, queueResetID: queueResetID)
    }
}
