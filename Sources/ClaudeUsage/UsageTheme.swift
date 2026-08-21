import SwiftUI
import ClaudeUsageCore

/// Maps a percentage to a tier, using the user's thresholds rather than the
/// server's `severity` so the two cannot disagree on screen. The server value
/// is still shown as a tooltip in the popover.
enum UsageTier {
    case normal
    case warning
    case critical

    @MainActor
    static func forPercent(_ percent: Int, preferences: Preferences) -> UsageTier {
        if percent >= preferences.criticalThreshold { return .critical }
        if percent >= preferences.warningThreshold { return .warning }
        return .normal
    }

    var color: Color {
        switch self {
        case .normal: return .accentColor
        case .warning: return .orange
        case .critical: return .red
        }
    }

    var nsColor: NSColor {
        switch self {
        case .normal: return .controlAccentColor
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }
}

extension UsageSnapshot {
    /// The limit the collapsed menu bar should track.
    func limit(for source: MenuBarSource) -> UsageLimit? {
        switch source {
        case .active:
            return activeLimit
        case .session:
            return limits.first { $0.group == "session" } ?? activeLimit
        case .weekly:
            return limits.first { $0.kind == "weekly_all" }
                ?? limits.first { $0.group == "weekly" }
                ?? activeLimit
        case .highest:
            return limits.max { $0.percent < $1.percent }
        }
    }
}

enum RelativeTime {
    /// "2h 14m" style countdown. Returns nil once the date has passed.
    static func compactCountdown(to date: Date, from now: Date = Date()) -> String? {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return nil }

        let totalMinutes = Int(seconds / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(minutes, 1))m"
    }

    static func clockTime(_ date: Date, use24Hour: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate(use24Hour ? "EEE HH:mm" : "EEE h:mm a")
        return formatter.string(from: date)
    }

    static func agoDescription(_ date: Date, from now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}
