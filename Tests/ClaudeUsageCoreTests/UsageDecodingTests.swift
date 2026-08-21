import Foundation
import Testing
@testable import ClaudeUsageCore

/// Recorded from the live endpoint, including the codenamed buckets that must
/// be ignored and two keys that were not in the documented shape.
private let recordedPayload = """
{
  "five_hour": {"utilization": 45.0, "resets_at": "2026-08-21T15:09:59.959400+00:00", "limit_dollars": null},
  "seven_day": {"utilization": 52.0, "resets_at": "2026-08-22T22:59:59.959443+00:00"},
  "nimbus_quill": null, "tangelo": null, "iguana_necktie": null,
  "seven_day_oauth_apps": null, "seven_day_omelette": null,
  "limits": [
    {"kind": "session", "group": "session", "percent": 45, "severity": "normal",
     "resets_at": "2026-08-21T15:09:59.959400+00:00", "scope": null, "is_active": false},
    {"kind": "weekly_all", "group": "weekly", "percent": 52, "severity": "normal",
     "resets_at": "2026-08-22T22:59:59.959443+00:00", "scope": null, "is_active": true},
    {"kind": "weekly_scoped", "group": "weekly", "percent": 38, "severity": "normal",
     "resets_at": "2026-08-22T22:59:59.959695+00:00",
     "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": false}
  ],
  "spend": {"used": {"amount_minor": 0, "currency": "USD", "exponent": 2},
            "limit": null, "percent": 0, "enabled": false},
  "member_dashboard_available": false
}
""".data(using: .utf8)!

@Suite("Usage decoding")
struct UsageDecodingTests {
    @Test("Decodes the recorded live payload")
    func decodesLivePayload() throws {
        let snapshot = try UsageClient.decodeSnapshot(from: recordedPayload, fetchedAt: Date())
        #expect(snapshot.limits.count == 3)
        #expect(snapshot.spend?.enabled == false)
    }

    @Test("Fractional second timestamps parse to the right instant")
    func parsesFractionalSeconds() throws {
        // Built from components rather than a hardcoded epoch, so the test
        // cannot silently encode its own arithmetic mistake.
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 21
        components.hour = 15
        components.minute = 9
        components.second = 59
        components.timeZone = TimeZone(identifier: "UTC")
        let expected = try #require(Calendar(identifier: .gregorian).date(from: components))

        let snapshot = try UsageClient.decodeSnapshot(from: recordedPayload, fetchedAt: Date())
        let session = try #require(snapshot.limits.first { $0.kind == "session" })
        let resets = try #require(session.resetsAt)

        // Within a second of the whole second value, so the fractional part is
        // parsed rather than causing a fallback to some other instant.
        #expect(abs(resets.timeIntervalSince(expected)) < 1)
    }

    @Test("Timestamps without fractional seconds still parse")
    func parsesWholeSeconds() {
        #expect(ISO8601.date(from: "2026-08-21T15:09:59Z") != nil)
        #expect(ISO8601.date(from: "2026-08-21T15:09:59+00:00") != nil)
        #expect(ISO8601.date(from: "not a date") == nil)
    }

    @Test("The binding limit is the one marked active")
    func picksActiveLimit() throws {
        let snapshot = try UsageClient.decodeSnapshot(from: recordedPayload, fetchedAt: Date())
        #expect(snapshot.activeLimit?.kind == "weekly_all")
    }

    @Test("Falls back to the highest limit when none is marked active")
    func fallsBackToHighest() {
        let snapshot = UsageSnapshot(fetchedAt: Date(), limits: [
            UsageLimit(kind: "session", group: "session", percent: 10),
            UsageLimit(kind: "weekly_all", group: "weekly", percent: 80),
        ])
        #expect(snapshot.activeLimit?.percent == 80)
    }

    @Test("An unknown severity does not fail the whole decode")
    func toleratesUnknownSeverity() throws {
        let payload = """
        {"limits": [{"kind": "session", "group": "session", "percent": 5,
          "severity": "apocalyptic", "resets_at": null, "scope": null, "is_active": true}]}
        """.data(using: .utf8)!
        let snapshot = try UsageClient.decodeSnapshot(from: payload, fetchedAt: Date())
        #expect(snapshot.limits.first?.severity == .unknown)
    }

    @Test("An unknown limit kind survives and gets a readable label")
    func toleratesUnknownKind() throws {
        let payload = """
        {"limits": [{"kind": "monthly_all", "group": "monthly", "percent": 12,
          "severity": "normal", "resets_at": null, "scope": null, "is_active": false}]}
        """.data(using: .utf8)!
        let snapshot = try UsageClient.decodeSnapshot(from: payload, fetchedAt: Date())
        let limit = try #require(snapshot.limits.first)
        #expect(limit.displayName == "Monthly All")
    }

    @Test("A missing limits array decodes to empty rather than throwing")
    func toleratesMissingLimits() throws {
        let payload = #"{"member_dashboard_available": false}"#.data(using: .utf8)!
        let snapshot = try UsageClient.decodeSnapshot(from: payload, fetchedAt: Date())
        #expect(snapshot.limits.isEmpty)
    }

    @Test("Scoped weekly limits name their model")
    func namesScopedModel() throws {
        let snapshot = try UsageClient.decodeSnapshot(from: recordedPayload, fetchedAt: Date())
        let scoped = try #require(snapshot.limits.first { $0.kind == "weekly_scoped" })
        #expect(scoped.displayName == "Weekly, Fable")
        #expect(scoped.shortDisplayName == "Fable")
    }

    @Test("Money is read as minor units with an exponent")
    func readsMinorUnits() {
        let money = MoneyAmount(amountMinor: 1234, currency: "USD", exponent: 2)
        #expect(money.decimalValue == Decimal(string: "12.34"))
    }

    @Test("Limit ids are stable and distinguish scoped rows")
    func stableIdentifiers() throws {
        let snapshot = try UsageClient.decodeSnapshot(from: recordedPayload, fetchedAt: Date())
        let ids = Set(snapshot.limits.map(\.id))
        #expect(ids.count == 3)
    }

    @Test("Rows sort session first, then weekly")
    func sortsByGroup() throws {
        let snapshot = try UsageClient.decodeSnapshot(from: recordedPayload, fetchedAt: Date())
        #expect(snapshot.sortedLimits.map(\.kind) == ["session", "weekly_all", "weekly_scoped"])
    }
}
