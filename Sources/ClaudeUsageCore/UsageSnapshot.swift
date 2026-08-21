import Foundation

/// Severity as reported by the server. Unknown values decode to `.unknown`
/// rather than failing, so a new severity tier cannot break a poll.
public enum LimitSeverity: String, Codable, Sendable, CaseIterable {
    case normal
    case warning
    case critical
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LimitSeverity(rawValue: raw) ?? .unknown
    }
}

/// The scope a limit applies to, when it is narrower than the whole account.
public struct LimitScope: Codable, Sendable, Equatable, Hashable {
    public struct Model: Codable, Sendable, Equatable, Hashable {
        public let id: String?
        public let displayName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }

    public let model: Model?
    public let surface: String?
}

/// One entry from the endpoint's `limits[]` array.
///
/// `kind` and `group` stay raw strings on purpose. The server adds new limit
/// kinds without warning, and a hardcoded enum would drop them on the floor.
public struct UsageLimit: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let kind: String
    public let group: String
    public let percent: Int
    public let severity: LimitSeverity
    public let resetsAt: Date?
    public let scope: LimitScope?
    public let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case kind, group, percent, severity, scope
        case resetsAt = "resets_at"
        case isActive = "is_active"
    }

    /// Stable across polls, so SwiftUI does not rebuild rows on every refresh.
    public var id: String {
        var parts = [kind, group]
        if let model = scope?.model?.displayName { parts.append(model) }
        if let surface = scope?.surface { parts.append(surface) }
        return parts.joined(separator: "/")
    }

    public init(
        kind: String,
        group: String,
        percent: Int,
        severity: LimitSeverity = .normal,
        resetsAt: Date? = nil,
        scope: LimitScope? = nil,
        isActive: Bool = false
    ) {
        self.kind = kind
        self.group = group
        self.percent = percent
        self.severity = severity
        self.resetsAt = resetsAt
        self.scope = scope
        self.isActive = isActive
    }
}

/// Money as the endpoint reports it: minor units plus an exponent.
public struct MoneyAmount: Codable, Sendable, Equatable {
    public let amountMinor: Int
    public let currency: String
    public let exponent: Int

    enum CodingKeys: String, CodingKey {
        case amountMinor = "amount_minor"
        case currency, exponent
    }

    public var decimalValue: Decimal {
        Decimal(amountMinor) / pow(Decimal(10), exponent)
    }
}

public struct SpendInfo: Codable, Sendable, Equatable {
    public let used: MoneyAmount?
    public let limit: MoneyAmount?
    public let percent: Int?
    public let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case used, limit, percent, enabled
    }
}

/// One poll of the usage endpoint, normalized down to what the UI needs.
///
/// Deliberately drops the endpoint's top level codenamed buckets
/// (`nimbus_quill`, `tangelo`, and friends). Those are unreleased internal
/// limits, almost always null, and must never reach the UI.
public struct UsageSnapshot: Codable, Sendable, Equatable {
    public let fetchedAt: Date
    public let limits: [UsageLimit]
    public let spend: SpendInfo?

    public init(fetchedAt: Date, limits: [UsageLimit], spend: SpendInfo? = nil) {
        self.fetchedAt = fetchedAt
        self.limits = limits
        self.spend = spend
    }

    /// The limit currently binding, which is what the collapsed menu bar shows.
    /// Falls back to the highest percentage when the server marks none active,
    /// so the menu bar is never blank on a valid response.
    public var activeLimit: UsageLimit? {
        limits.first(where: \.isActive) ?? limits.max(by: { $0.percent < $1.percent })
    }

    public var sortedLimits: [UsageLimit] {
        limits.sorted { lhs, rhs in
            if lhs.group != rhs.group {
                return Self.groupRank(lhs.group) < Self.groupRank(rhs.group)
            }
            if lhs.percent != rhs.percent { return lhs.percent > rhs.percent }
            return lhs.id < rhs.id
        }
    }

    private static func groupRank(_ group: String) -> Int {
        switch group {
        case "session": return 0
        case "weekly": return 1
        default: return 2
        }
    }
}

/// Raw decode target for the endpoint response. Only the fields we trust.
struct UsageEndpointResponse: Decodable {
    let limits: [UsageLimit]?
    let spend: SpendInfo?
    let memberDashboardAvailable: Bool?

    enum CodingKeys: String, CodingKey {
        case limits, spend
        case memberDashboardAvailable = "member_dashboard_available"
    }
}
