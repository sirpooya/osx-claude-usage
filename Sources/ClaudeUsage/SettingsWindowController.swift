import AppKit
import SwiftUI

/// A plain NSWindow hosting the SwiftUI settings.
///
/// An agent app has no Settings scene to hang off, so the window is created and
/// held here. It is kept alive rather than recreated so tab selection and
/// window position survive closing and reopening.
@MainActor
final class SettingsWindowController {
    private static let contentSize = NSSize(width: 460, height: 380)

    private let window: NSWindow

    init(viewModel: UsageViewModel, preferences: Preferences) {
        // The style mask has to be passed to the initializer. Assigning it
        // afterwards leaves the hosted content view unsized, which paints the
        // title bar and nothing else.
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = NSHostingController(
            rootView: SettingsView(viewModel: viewModel, preferences: preferences)
        )
        window.title = "ClaudeUsage Settings"
        window.isReleasedWhenClosed = false
        window.setContentSize(Self.contentSize)
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
