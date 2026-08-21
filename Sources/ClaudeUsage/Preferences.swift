import Foundation
import Observation

/// What the collapsed menu bar shows.
public enum MenuBarStyle: String, CaseIterable, Identifiable, Sendable {
    case percent
    case labelAndPercent
    case iconOnly

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .percent: return "Percentage"
        case .labelAndPercent: return "Label and percentage"
        case .iconOnly: return "Icon only"
        }
    }
}

/// Which limit the collapsed menu bar tracks.
public enum MenuBarSource: String, CaseIterable, Identifiable, Sendable {
    case active
    case session
    case weekly
    case highest

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return "Whichever limit is binding"
        case .session: return "Session window"
        case .weekly: return "Weekly"
        case .highest: return "Highest of all"
        }
    }
}

/// UserDefaults backed settings. Single source of truth for the UI.
@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()

    private enum Key {
        static let menuBarStyle = "menuBarStyle"
        static let menuBarSource = "menuBarSource"
        static let showColorWhenHigh = "showColorWhenHigh"
        static let warningThreshold = "warningThreshold"
        static let criticalThreshold = "criticalThreshold"
        static let use24HourClock = "use24HourClock"
        static let launchAtLogin = "launchAtLogin"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.menuBarStyle: MenuBarStyle.labelAndPercent.rawValue,
            Key.menuBarSource: MenuBarSource.active.rawValue,
            Key.showColorWhenHigh: true,
            Key.warningThreshold: 75,
            Key.criticalThreshold: 90,
            Key.use24HourClock: false,
        ])
        _menuBarStyle = MenuBarStyle(rawValue: defaults.string(forKey: Key.menuBarStyle) ?? "") ?? .labelAndPercent
        _menuBarSource = MenuBarSource(rawValue: defaults.string(forKey: Key.menuBarSource) ?? "") ?? .active
        _showColorWhenHigh = defaults.bool(forKey: Key.showColorWhenHigh)
        _warningThreshold = defaults.integer(forKey: Key.warningThreshold)
        _criticalThreshold = defaults.integer(forKey: Key.criticalThreshold)
        _use24HourClock = defaults.bool(forKey: Key.use24HourClock)
    }

    private var _menuBarStyle: MenuBarStyle
    var menuBarStyle: MenuBarStyle {
        get { _menuBarStyle }
        set { _menuBarStyle = newValue; defaults.set(newValue.rawValue, forKey: Key.menuBarStyle) }
    }

    private var _menuBarSource: MenuBarSource
    var menuBarSource: MenuBarSource {
        get { _menuBarSource }
        set { _menuBarSource = newValue; defaults.set(newValue.rawValue, forKey: Key.menuBarSource) }
    }

    private var _showColorWhenHigh: Bool
    var showColorWhenHigh: Bool {
        get { _showColorWhenHigh }
        set { _showColorWhenHigh = newValue; defaults.set(newValue, forKey: Key.showColorWhenHigh) }
    }

    private var _warningThreshold: Int
    var warningThreshold: Int {
        get { _warningThreshold }
        set { _warningThreshold = newValue; defaults.set(newValue, forKey: Key.warningThreshold) }
    }

    private var _criticalThreshold: Int
    var criticalThreshold: Int {
        get { _criticalThreshold }
        set { _criticalThreshold = newValue; defaults.set(newValue, forKey: Key.criticalThreshold) }
    }

    private var _use24HourClock: Bool
    var use24HourClock: Bool {
        get { _use24HourClock }
        set { _use24HourClock = newValue; defaults.set(newValue, forKey: Key.use24HourClock) }
    }
}
