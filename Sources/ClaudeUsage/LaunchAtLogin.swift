import Foundation
import ServiceManagement

/// Wraps SMAppService so the settings toggle has somewhere honest to read from.
/// Only meaningful for a real .app bundle, so it reports unavailable when the
/// executable is run loose from the command line.
@MainActor
enum LaunchAtLogin {
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    static var isEnabled: Bool {
        guard isAvailable else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Returns the resulting state, which may differ from the request if the
    /// user has the login item disabled in System Settings.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard isAvailable else { return false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            return isEnabled
        }
        return isEnabled
    }
}
