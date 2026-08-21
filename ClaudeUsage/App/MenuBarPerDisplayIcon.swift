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

    // MARK: - Inactive-bar dimming

    /// macOS dims menu bar items on the display whose menu bar is inactive, but only through
    /// the template tint. Color images are drawn literally and never dim, so a color status
    /// icon stays full-brightness next to everyone else's dimmed icons. The fix: read which
    /// display's menu bar is active (private SkyLight call, runtime-guarded) and dim our own
    /// renders on the other bars to match.

    /// Alpha applied to the icon on an inactive menu bar, eyeballed against the system's
    /// dimming of template icons.
    static let inactiveDimAlpha: CGFloat = 0.45

    private typealias MainConnFn = @convention(c) () -> Int32
    private typealias ActiveMenuBarFn = @convention(c) (Int32) -> Unmanaged<CFString>?
    private typealias UUIDFromIDFn = @convention(c) (UInt32) -> Unmanaged<CFUUID>?

    private static let skyLightHandle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)

    private static let mainConnectionFn: MainConnFn? = {
        guard let handle = skyLightHandle, let sym = dlsym(handle, "SLSMainConnectionID") else { return nil }
        return unsafeBitCast(sym, to: MainConnFn.self)
    }()

    private static let activeMenuBarFn: ActiveMenuBarFn? = {
        guard let handle = skyLightHandle, let sym = dlsym(handle, "SLSCopyActiveMenuBarDisplayIdentifier") else { return nil }
        return unsafeBitCast(sym, to: ActiveMenuBarFn.self)
    }()

    /// CGDisplayCreateUUIDFromDisplayID is public but deprecated; dlsym keeps the build clean
    private static let uuidFromDisplayIDFn: UUIDFromIDFn? = {
        guard let handle = dlopen(nil, RTLD_NOW), let sym = dlsym(handle, "CGDisplayCreateUUIDFromDisplayID") else { return nil }
        return unsafeBitCast(sym, to: UUIDFromIDFn.self)
    }()

    /// UUID string of the display whose menu bar is currently active, nil when the private
    /// call is unavailable
    private static func activeMenuBarDisplayUUID() -> String? {
        guard let mainConnection = mainConnectionFn, let active = activeMenuBarFn,
              let uuid = active(mainConnection())?.takeRetainedValue() else { return nil }
        return uuid as String
    }

    /// Whether the menu bar hosting this window is the active one. true when any part of the
    /// signal is unavailable, which keeps the icon at full brightness (the old behavior).
    static func isBarActive(on window: NSWindow) -> Bool {
        guard let active = activeMenuBarDisplayUUID(),
              let screen = window.screen,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuidFn = uuidFromDisplayIDFn,
              let uuid = uuidFn(number.uint32Value)?.takeRetainedValue()
        else { return true }
        let uuidString = CFUUIDCreateString(nil, uuid) as String
        return uuidString.caseInsensitiveCompare(active) == .orderedSame
    }

    /// Flattened copy of the image at reduced alpha, for inactive menu bars
    static func dimmed(_ image: NSImage, alpha: CGFloat = inactiveDimAlpha) -> NSImage {
        let out = NSImage(size: image.size)
        out.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: image.size), from: .zero, operation: .sourceOver, fraction: alpha)
        out.unlockFocus()
        return out
    }

    /// Fix A: appearance-resolving wrapper. The render closure re-runs per menu bar draw
    /// with UsageColorScheme.drawingIsDarkOverride pinned to that bar's appearance.
    /// Only useful for color icons; template icons already adapt natively.
    static func dynamicImage(size: NSSize, render: @escaping (Bool) -> NSImage) -> NSImage {
        return NSImage(size: size, flipped: false) { rect in
            let isDark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
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
            button.image = isBarActive(on: window) ? image : dimmed(image)
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
