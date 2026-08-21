import Foundation
import Testing
@testable import ClaudeUsageCore

@Suite("Poll pacing")
struct PollPolicyTests {
    @Test("Polls at the active cadence right after usage moves")
    func activeCadence() {
        let now = Date()
        let policy = PollPolicy(lastChangeAt: now)
        #expect(policy.nextInterval(now: now) == PollPolicy.activeInterval)
    }

    @Test("Backs off once usage has been still for a while")
    func idleCadence() {
        let now = Date()
        let policy = PollPolicy(lastChangeAt: now.addingTimeInterval(-30 * 60))
        #expect(policy.nextInterval(now: now) == PollPolicy.idleInterval)
    }

    @Test("Backs off further after an hour of quiet")
    func deepIdleCadence() {
        let now = Date()
        let policy = PollPolicy(lastChangeAt: now.addingTimeInterval(-3 * 3600))
        #expect(policy.nextInterval(now: now) == PollPolicy.deepIdleInterval)
    }

    @Test("Failures back off exponentially and stay capped")
    func exponentialBackoff() {
        var policy = PollPolicy(lastChangeAt: Date())
        var seen: [TimeInterval] = []
        for _ in 0..<10 {
            policy.recordFailure(UsageClientError.httpStatus(500))
            seen.append(policy.nextInterval())
        }
        #expect(seen[0] == 60)
        #expect(seen[1] == 120)
        #expect(seen[2] == 240)
        #expect(seen.allSatisfy { $0 <= PollPolicy.maximumBackoff })
        #expect(seen.last == PollPolicy.maximumBackoff)
    }

    @Test("A Retry-After header wins over our own pacing")
    func honorsRetryAfter() {
        var policy = PollPolicy(lastChangeAt: Date())
        policy.recordFailure(UsageClientError.rateLimited(retryAfter: 420))
        #expect(policy.nextInterval() == 420)
    }

    @Test("A 429 with no Retry-After still waits a long time")
    func bare429WaitsLong() {
        var policy = PollPolicy(lastChangeAt: Date())
        policy.recordFailure(UsageClientError.rateLimited(retryAfter: nil))
        #expect(policy.nextInterval() >= 300)
    }

    @Test("Never polls faster than the 30 second floor")
    func respectsFloor() {
        var policy = PollPolicy(lastChangeAt: Date())
        policy.recordFailure(UsageClientError.rateLimited(retryAfter: 1))
        #expect(policy.nextInterval() == PollPolicy.hardMinimumInterval)
    }

    @Test("A success clears the backoff")
    func successResetsBackoff() {
        var policy = PollPolicy(lastChangeAt: Date())
        policy.recordFailure(UsageClientError.httpStatus(500))
        policy.recordFailure(UsageClientError.httpStatus(500))
        policy.recordSuccess(changed: true)
        #expect(policy.failureCount == 0)
        #expect(policy.retryAfter == nil)
        #expect(policy.nextInterval() == PollPolicy.activeInterval)
    }

    @Test("A poll that changes nothing but the timestamp is not a change")
    func timestampAloneIsNotAChange() {
        let limits = [UsageLimit(kind: "session", group: "session", percent: 40, isActive: true)]
        let first = UsageSnapshot(fetchedAt: Date(), limits: limits)
        let second = UsageSnapshot(fetchedAt: Date().addingTimeInterval(60), limits: limits)
        #expect(second.differsMeaningfully(from: first) == false)
    }

    @Test("A percentage move counts as a change")
    func percentMoveIsAChange() {
        let first = UsageSnapshot(fetchedAt: Date(), limits: [
            UsageLimit(kind: "session", group: "session", percent: 40),
        ])
        let second = UsageSnapshot(fetchedAt: Date(), limits: [
            UsageLimit(kind: "session", group: "session", percent: 41),
        ])
        #expect(second.differsMeaningfully(from: first))
    }
}
