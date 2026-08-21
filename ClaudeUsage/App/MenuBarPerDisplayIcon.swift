//
//  MenuBarPerDisplayIcon.swift
//  ClaudeUsage
//
//  Per-display menu bar icon support.
//
//  One NSStatusItem holds one NSImage and macOS shows that item on every display, so a
//  color icon whose grays were resolved against one menu bar is wrong on a second display
//  whose wallpaper gives the bar the opposite appearance. Template images do not have the
//  problem because AppKit re-tints them per bar; color images are drawn literally.
//
//  What makes a fix possible at all: the app itself hosts one NSStatusBarWindow per
//  display. The primary one carries the real NSStatusItem, the secondary ones carry the
//  private NSStatusItemReplicant, and all of them are reachable through NSApp.windows.
//  Each window draws the icon separately with its own effectiveAppearance.
//
//  Two fixes, applied together:
//  A. dynamicImage(size:render:) wraps the renderer in NSImage(size:flipped:drawingHandler:).
//     The handler runs per destination draw (NSImage caches per appearance since 10.14),
//     reads NSAppearance.currentDrawingAppearance, pins
//     UsageColorScheme.drawingIsDarkOverride and re-renders, so tonal parts resolve per
//     display while accent colors stay literal.
//  B. applyToReplicants(mainButton:render:) walks the NSStatusBarWindow instances, finds
//     each window's NSStatusBarButton, skips the main one, and assigns an image
//     force-rendered for that window's own effectiveAppearance. Belt and braces for the
//     case where a replicant draw does not re-resolve the dynamic image. AppKit may sync
//     the main image back over it later; harmless, because that image is fix A's.
//

import AppKit

enum MenuBarPerDisplayIcon {

    /// Fix A: appearance-resolving wrapper. The render closure re-runs per menu bar draw
    /// with UsageColorScheme.drawingIsDarkOverride pinned to that bar's appearance.
    /// Only useful for color icons; template icons already adapt natively.
    static func dynamicImage(size: NSSize, render: @escaping (Bool) -> NSImage) -> NSImage {
        return NSImage(size: size, flipped: false) { rect in
            let isDark = NSAppearance.currentDrawingAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            UsageColorScheme.drawingIsDarkOverride = isDark
            defer { UsageColorScheme.drawingIsDarkOverride = nil }
            render(isDark).draw(in: rect)
            return true
        }
    }

    /// Fix B: force-render one image per replicant window. No-op with a single display.
    static func applyToReplicants(mainButton: NSStatusBarButton?, render: (Bool) -> NSImage) {
        for window in statusBarWindows() {
            guard let button = statusBarButton(in: window), button !== mainButton else { continue }
            let isDark = window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            UsageColorScheme.drawingIsDarkOverride = isDark
            let image = render(isDark)
            UsageColorScheme.drawingIsDarkOverride = nil
            button.image = image
        }
    }

    /// This app's status bar windows: the main one plus one replicant per extra display.
    static func statusBarWindows() -> [NSWindow] {
        NSApp.windows.filter { String(describing: type(of: $0)).contains("NSStatusBarWindow") }
    }

    private static func statusBarButton(in window: NSWindow) -> NSStatusBarButton? {
        guard let root = window.contentView else { return nil }
        return firstStatusBarButton(in: root)
    }

    private static func firstStatusBarButton(in view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton { return button }
        for sub in view.subviews {
            if let found = firstStatusBarButton(in: sub) { return found }
        }
        return nil
    }
}
