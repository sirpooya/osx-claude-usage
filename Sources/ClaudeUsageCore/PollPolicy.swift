import Foundation

/// Decides how long to wait before the next poll.
///
/// Pure value type on purpose so the pacing rules can be tested without a
/// timer or a network. Floor of 30s is a hard rule, not a preference.
public struct PollPolicy: Sendable, Equatable {
    public static let hardMinimumInterval: TimeInterval = 30
    public static let activeInterval: TimeInterval = 60
    public static let idleInterval: TimeInterval = 300
    public static let deepIdleInterval: TimeInterval = 600
    /// A session counts as active while usage moved within this window.
    public static let activityWindow: TimeInterval = 15 * 60
    /// Past this much quiet, back all the way off.
    public static let deepIdleThreshold: TimeInterval = 60 * 60

    public static let maximumBackoff: TimeInterval = 15 * 60

    /// Consecutive failures. Drives exponential backoff.
    public var failureCount: Int = 0
    /// Server supplied wait from a 429, which always wins over our own pacing.
    public var retryAfter: TimeInterval?
    /// When usage percentages last changed.
    public var lastChangeAt: Date?

    public init(failureCount: Int = 0, retryAfter: TimeInterval? = nil, lastChangeAt: Date? = nil) {
        self.failureCount = failureCount
        self.retryAfter = retryAfter
        self.lastChangeAt = lastChangeAt
    }

    /// Base cadence ignoring failures, from how recently usage moved.
    public func baseInterval(now: Date = Date()) -> TimeInterval {
        guard let lastChangeAt else { return Self.idleInterval }
        let quiet = now.timeIntervalSince(lastChangeAt)
        if quiet <= Self.activityWindow { return Self.activeInterval }
        if quiet >= Self.deepIdleThreshold { return Self.deepIdleInterval }
        return Self.idleInterval
    }

    /// The interval to actually sleep for.
    public func nextInterval(now: Date = Date()) -> TimeInterval {
        if let retryAfter {
            return max(retryAfter, Self.hardMinimumInterval)
        }

        if failureCount > 0 {
            // 60, 120, 240, ... capped. Jitter is added by the caller.
            let scaled = Self.activeInterval * pow(2, Double(min(failureCount, 8) - 1))
            return min(max(scaled, Self.hardMinimumInterval), Self.maximumBackoff)
        }

        return max(baseInterval(now: now), Self.hardMinimumInterval)
    }

    public mutating func recordSuccess(changed: Bool, at date: Date = Date()) {
        failureCount = 0
        retryAfter = nil
        if changed || lastChangeAt == nil {
            lastChangeAt = date
        }
    }

    public mutating func recordFailure(_ error: any Error) {
        failureCount += 1
        if case UsageClientError.rateLimited(let after) = error {
            // Honor the server even when it does not send Retry-After, by
            // treating a bare 429 as a long wait rather than a fast retry.
            retryAfter = after ?? min(Self.maximumBackoff, Self.activeInterval * 5)
        } else {
            retryAfter = nil
        }
    }
}

extension UsageSnapshot {
    /// Whether two snapshots differ in anything a user would notice.
    /// `fetchedAt` alone must not count as a change or the poller never idles.
    public func differsMeaningfully(from other: UsageSnapshot?) -> Bool {
        guard let other else { return true }
        return limits != other.limits || spend != other.spend
    }
}
