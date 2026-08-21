import AppKit

/// Entry point. Deliberately AppKit rather than a SwiftUI App scene, because an
/// LSUIElement agent with a custom NSStatusItem wants direct control over
/// activation policy and window lifetime.
@main
enum AppMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        // NSApplication holds its delegate weakly, so keep a strong reference.
        Self.retainedDelegate = delegate
        app.delegate = delegate
        app.run()
    }

    @MainActor private static var retainedDelegate: AppDelegate?
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private let viewModel = UsageViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon and no main window, even when launched loose from the
        // command line where Info.plist LSUIElement does not apply.
        NSApp.setActivationPolicy(.accessory)

        statusItemController = StatusItemController(
            viewModel: viewModel,
            preferences: Preferences.shared
        )
        viewModel.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.stop()
    }

    /// Reopening from Finder or the Dock should surface settings, since there
    /// is no window to restore.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItemController?.openSettings()
        return true
    }
}
