import AppKit
import SwiftUI
import ClaudeUsageCore

/// Owns the NSStatusItem and the popover attached to it.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let viewModel: UsageViewModel
    private let preferences: Preferences
    private var settingsWindowController: SettingsWindowController?
    private var redrawTask: Task<Void, Never>?

    init(viewModel: UsageViewModel, preferences: Preferences) {
        self.viewModel = viewModel
        self.preferences = preferences
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton()
        configurePopover()
        startRedrawLoop()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "gauge.with.dots.needle.bottom.50percent",
            accessibilityDescription: "Claude usage"
        )
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                viewModel: viewModel,
                preferences: preferences,
                onOpenSettings: { [weak self] in self?.openSettings() },
                onQuit: { NSApp.terminate(nil) }
            )
        )
    }

    /// The title depends on values that change without a SwiftUI view in play,
    /// so it is refreshed on a slow tick rather than bound.
    private func startRedrawLoop() {
        redrawTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshTitle()
                try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
            }
        }
    }

    func refreshTitle() {
        guard let button = statusItem.button else { return }
        let failed = if case .failed = viewModel.state { true } else { false }

        button.attributedTitle = MenuBarTitle.attributedTitle(
            snapshot: viewModel.snapshot,
            preferences: preferences,
            failed: failed
        ) ?? NSAttributedString(string: "")

        button.toolTip = MenuBarTitle.tooltip(snapshot: viewModel.snapshot, preferences: preferences)
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { togglePopover(); return }

        // Right click and control click get a plain menu, which is faster than
        // the popover for the two things people actually want in a hurry.
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        viewModel.refreshNow()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh now", action: #selector(menuRefresh), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings...", action: #selector(menuSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit ClaudeUsage", action: #selector(menuQuit), keyEquivalent: "q").target = self

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Detach immediately or the menu hijacks every future left click.
        statusItem.menu = nil
    }

    @objc private func menuRefresh() { viewModel.refreshNow() }
    @objc private func menuSettings() { openSettings() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    func openSettings() {
        popover.performClose(nil)
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                viewModel: viewModel,
                preferences: preferences
            )
        }
        settingsWindowController?.show()
    }
}
