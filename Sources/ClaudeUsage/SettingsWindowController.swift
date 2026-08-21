import AppKit
import SwiftUI

/// A plain NSWindow hosting the SwiftUI settings.
///
/// An agent app has no Settings scene to hang off, so the window is created and
/// held here. It is kept alive rather than recreated so tab selection and
/// scroll position survive closing and reopening.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(viewModel: UsageViewModel, preferences: Preferences) {
        let hosting = NSHostingController(
            rootView: SettingsView(viewModel: viewModel, preferences: preferences)
        )

        window = NSWindow(contentViewController: hosting)
        window.title = "ClaudeUsage Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("ClaudeUsageSettings")
    }

    func show() {
        // An accessory app is not normally allowed to take focus, so ask for it
        // explicitly or the settings window opens behind everything.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
