import AppKit
import ClaudeUsageCore

/// Builds the collapsed menu bar title.
///
/// Digits are monospaced so the item does not shift width as the number
/// changes, which is the single most noticeable flaw in most trackers.
@MainActor
enum MenuBarTitle {
    static func attributedTitle(
        snapshot: UsageSnapshot?,
        preferences: Preferences,
        failed: Bool
    ) -> NSAttributedString? {
        guard preferences.menuBarStyle != .iconOnly else { return nil }

        guard let snapshot, let limit = snapshot.limit(for: preferences.menuBarSource) else {
            return NSAttributedString(
                string: failed ? "!" : "...",
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            )
        }

        let tier = UsageTier.forPercent(limit.percent, preferences: preferences)
        let color: NSColor = (preferences.showColorWhenHigh && tier != .normal)
            ? tier.nsColor
            : .labelColor

        let result = NSMutableAttributedString()

        if preferences.menuBarStyle == .labelAndPercent {
            result.append(NSAttributedString(
                string: limit.shortDisplayName + " ",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            ))
        }

        result.append(NSAttributedString(
            string: "\(limit.percent)%",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: color,
            ]
        ))

        return result
    }

    static func tooltip(snapshot: UsageSnapshot?, preferences: Preferences) -> String {
        guard let snapshot else { return "ClaudeUsage" }
        var lines = snapshot.sortedLimits.map { limit -> String in
            var line = "\(limit.displayName): \(limit.percent)%"
            if let resets = limit.resetsAt, let countdown = RelativeTime.compactCountdown(to: resets) {
                line += " (resets in \(countdown))"
            }
            return line
        }
        if lines.isEmpty { lines = ["No limits reported"] }
        lines.append("Updated \(RelativeTime.agoDescription(snapshot.fetchedAt))")
        return lines.joined(separator: "\n")
    }
}
