import AppKit
import SwiftUI

private enum ProjectLinks {
    static let website = URL(string: "https://ixiehao.github.io/ShotMap/")!
    static let repository = URL(string: "https://github.com/ixiehao/ShotMap")!
    static let issues = URL(string: "https://github.com/ixiehao/ShotMap/issues/new/choose")!
}

private enum AboutCredits {
    static func make(language: AppLanguage, availableUpdate: AvailableUpdate?) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 5

        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]
        let linkAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.linkColor,
            .paragraphStyle: paragraph,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        let credits = NSMutableAttributedString()

        func appendBody(_ text: String) {
            credits.append(NSAttributedString(string: text, attributes: bodyAttributes))
        }

        func appendLink(_ text: String, destination: URL) {
            var attributes = linkAttributes
            attributes[.link] = destination
            credits.append(NSAttributedString(string: text, attributes: attributes))
        }

        appendBody("\(language.text("about.developer")) · ixiehao\n")
        appendLink("ixiehao.github.io/ShotMap\n", destination: ProjectLinks.website)
        appendLink(language.text("about.feedback"), destination: ProjectLinks.issues)
        if let availableUpdate {
            appendBody("\n\n\(language.text("update.about.available", availableUpdate.version))\n")
            appendLink(language.text("button.downloadUpdate"), destination: availableUpdate.downloadURL)
        }
        appendBody("\n\n\(language.text("about.privacy"))\n\(language.text("about.license"))")
        return credits
    }
}

private struct HelpStep: View {
    let index: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Text(index)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct HelpPanel: View {
    let language: AppLanguage
    @ObservedObject var updateChecker: UpdateChecker

    private func t(_ key: String) -> String {
        language.text(key)
    }

    private var icon: NSImage {
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: iconURL) {
            return image
        }
        return NSApplication.shared.applicationIconImage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("help.title"))
                        .font(.system(size: 18, weight: .bold))
                    Text(t("help.intro"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            if updateChecker.hasUpdate {
                UpdateAvailableBanner(checker: updateChecker, language: language)
                    .frame(maxWidth: .infinity, alignment: .center)
                Divider()
            }

            VStack(alignment: .leading, spacing: 14) {
                HelpStep(index: "1", title: t("help.step.add.title"), detail: t("help.step.add.detail"))
                HelpStep(index: "2", title: t("help.step.settings.title"), detail: t("help.step.settings.detail"))
                HelpStep(index: "3", title: t("help.step.create.title"), detail: t("help.step.create.detail"))
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text(t("help.troubleshoot.title"))
                    .font(.system(size: 13, weight: .semibold))
                Text(t("help.troubleshoot.detail"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(t("help.privacy"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Link(t("help.project"), destination: ProjectLinks.repository)
                    .buttonStyle(.bordered)
                Link(t("help.feedback"), destination: ProjectLinks.issues)
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}

/// SwiftUI creates the window, while AppKit handles the macOS Dock lifecycle.
/// In particular, a Dock click after miniaturising the only window must bring
/// that existing window back instead of leaving the application active but
/// invisible.
enum MainWindowReopenAction: Equatable {
    case create, restore, none

    static func resolve(hasMainWindow: Bool, isVisible: Bool, isMiniaturized: Bool) -> Self {
        guard hasMainWindow else { return .create }
        return !isVisible || isMiniaturized ? .restore : .none
    }
}

@MainActor
final class ShotMapAppDelegate: NSObject, NSApplicationDelegate {
    private var helpWindow: NSWindow?
    private weak var mainWindow: NSWindow?
    private var mainWindowCloseObserver: NSObjectProtocol?
    private var openMainWindow: (() -> Void)?
    private var shouldFocusNextMainWindow = false

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // SwiftUI does not recreate a WindowGroup merely because this delegate
        // returns false. Keep its OpenWindowAction and invoke it explicitly.
        // This avoids the old broad lookup, which could restore a hidden Help
        // window instead of the application's primary window.
        // `flag` includes Help/About windows. Only the main window determines
        // whether clicking the Dock must recreate or restore the workspace.
        let action = MainWindowReopenAction.resolve(
            hasMainWindow: mainWindow != nil,
            isVisible: mainWindow?.isVisible ?? false,
            isMiniaturized: mainWindow?.isMiniaturized ?? false
        )
        if action == .create {
            shouldFocusNextMainWindow = openMainWindow != nil
            openMainWindow?()
            sender.activate(ignoringOtherApps: true)
            return openMainWindow != nil
        }
        guard action == .restore, let mainWindow else { return true }
        Task { @MainActor [weak self] in
            self?.restore(mainWindow, in: sender)
        }
        return true
    }

    @MainActor
    func configureMainWindowOpener(_ opener: @escaping () -> Void) {
        openMainWindow = opener
    }

    @MainActor
    func registerMainWindow(_ window: NSWindow) {
        guard window !== self.helpWindow, window !== self.mainWindow else { return }
        self.mainWindowCloseObserver.map(NotificationCenter.default.removeObserver)
        self.mainWindow = window
        let registeredWindowID = ObjectIdentifier(window)
        self.mainWindowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self?.mainWindow.map(ObjectIdentifier.init) == registeredWindowID else { return }
                self?.mainWindow = nil
            }
        }
        if shouldFocusNextMainWindow {
            shouldFocusNextMainWindow = false
            restore(window, in: NSApplication.shared)
        }
    }

    @MainActor
    private func restore(_ window: NSWindow, in application: NSApplication) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        application.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor
    func showAboutPanel(language: AppLanguage, updateChecker: UpdateChecker) {
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .credits: AboutCredits.make(language: language, availableUpdate: updateChecker.availableUpdate)
        ])
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @MainActor
    func showHelpPanel(language: AppLanguage, updateChecker: UpdateChecker) {
        let window: NSWindow
        if let existingWindow = helpWindow {
            window = existingWindow
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 460),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.center()
            helpWindow = window
        }

        window.title = language.text("help.title")
        window.contentView = NSHostingView(rootView: HelpPanel(language: language, updateChecker: updateChecker))
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// Retains SwiftUI's scene-opening action after the main window closes, so the
/// AppKit Dock callback can create a fresh WindowGroup instance on macOS 13+.
private struct MainWindowLifecycleBridge: View {
    let appDelegate: ShotMapAppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MainWindowRegistrationView(appDelegate: appDelegate)
            .frame(width: 0, height: 0)
            .onAppear {
                let action = openWindow
                appDelegate.configureMainWindowOpener {
                    action(id: "main")
                }
            }
    }
}

private struct MainWindowRegistrationView: NSViewRepresentable {
    let appDelegate: ShotMapAppDelegate

    func makeNSView(context: Context) -> RegistrationView {
        let view = RegistrationView()
        view.register = { [weak appDelegate] window in
            appDelegate?.registerMainWindow(window)
        }
        return view
    }

    func updateNSView(_ nsView: RegistrationView, context: Context) { }

    final class RegistrationView: NSView {
        var register: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { register?(window) }
        }
    }
}

@main
struct ShotMapApp: App {
    @NSApplicationDelegateAdaptor(ShotMapAppDelegate.self) private var appDelegate
    @AppStorage("appLanguage") private var languageCode = AppLanguage.chinese.rawValue
    @StateObject private var updateChecker = UpdateChecker()
    @StateObject private var storyboardModel = StoryboardViewModel()

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .chinese
    }

    var body: some Scene {
        Window("ShotMap", id: "main") {
            ContentView(model: storyboardModel)
                .environmentObject(updateChecker)
                .frame(minWidth: 940, minHeight: 640)
                // The hidden title bar is part of the composition: the toolbar
                // can use it because its leading content already clears the
                // traffic lights. Do not retain an empty safe-area strip.
                .ignoresSafeArea(.container, edges: .top)
                .background(MainWindowLifecycleBridge(appDelegate: appDelegate))
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(language.text("about.menu")) {
                    appDelegate.showAboutPanel(language: language, updateChecker: updateChecker)
                }
            }

            CommandGroup(replacing: .help) {
                Button(language.text("help.menu")) {
                    appDelegate.showHelpPanel(language: language, updateChecker: updateChecker)
                }
                Divider()
                Button(updateChecker.hasUpdate ? language.text("update.menu.available", updateChecker.availableUpdate?.version ?? "") : language.text("update.menu.check")) {
                    if updateChecker.hasUpdate {
                        updateChecker.openDownloadPage()
                    } else {
                        Task { await updateChecker.checkForUpdate(force: true) }
                    }
                }
                Divider()
                Button(language.text("help.project")) {
                    NSWorkspace.shared.open(ProjectLinks.repository)
                }
                Button(language.text("help.feedback")) {
                    NSWorkspace.shared.open(ProjectLinks.issues)
                }
            }
        }
    }
}
