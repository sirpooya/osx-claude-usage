import Foundation

extension UsageLimit {
    /// Human readable label for a limit row.
    ///
    /// Known kinds get a curated name. Unknown kinds get their raw identifier
    /// humanized instead of being hidden, because `limits[]` entries are self
    /// describing and a new kind is real usage the user should still see.
    public var displayName: String {
        switch kind {
        case "session":
            return "Session"
        case "weekly_all":
            return "Weekly"
        case "weekly_scoped":
            if let model = scope?.model?.displayName {
                return "Weekly, \(model)"
            }
            if let surface = scope?.surface {
                return "Weekly, \(surface)"
            }
            return "Weekly, scoped"
        default:
            return Self.humanize(kind)
        }
    }

    /// A short label for tight spaces such as the menu bar.
    public var shortDisplayName: String {
        switch kind {
        case "session":
            return "5h"
        case "weekly_all":
            return "Week"
        case "weekly_scoped":
            return scope?.model?.displayName ?? "Week"
        default:
            return Self.humanize(kind)
        }
    }

    /// `weekly_all` becomes `Weekly All`.
    static func humanize(_ raw: String) -> String {
        raw
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    public var fraction: Double {
        min(max(Double(percent) / 100.0, 0), 1)
    }
}
