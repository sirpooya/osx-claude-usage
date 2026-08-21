import Foundation
import Testing
@testable import ClaudeUsageCore

@Suite("History store")
struct HistoryStoreTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("claudeusage-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("history.jsonl")
    }

    private func snapshot(percent: Int, at date: Date) -> UsageSnapshot {
        UsageSnapshot(fetchedAt: date, limits: [
            UsageLimit(kind: "session", group: "session", percent: percent, isActive: true),
        ])
    }

    @Test("Writes the first snapshot and reads it back")
    func roundTrip() async throws {
        let store = HistoryStore(fileURL: tempURL())
        let now = Date()
        #expect(await store.record(snapshot(percent: 10, at: now)))

        let loaded = await store.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.limits.first?.percent == 10)
    }

    @Test("Appends rather than overwriting")
    func appends() async {
        let store = HistoryStore(fileURL: tempURL())
        let now = Date()
        await store.record(snapshot(percent: 10, at: now))
        await store.record(snapshot(percent: 11, at: now.addingTimeInterval(60)))
        await store.record(snapshot(percent: 12, at: now.addingTimeInterval(120)))
        #expect(await store.rowCount() == 3)
    }

    @Test("Skips an unchanged snapshot inside the heartbeat window")
    func skipsUnchanged() async {
        let store = HistoryStore(fileURL: tempURL())
        let now = Date()
        #expect(await store.record(snapshot(percent: 10, at: now)))
        #expect(await store.record(snapshot(percent: 10, at: now.addingTimeInterval(60))) == false)
        #expect(await store.rowCount() == 1)
    }

    @Test("Writes an unchanged snapshot once the heartbeat elapses, so flat stretches still chart")
    func heartbeatAnchors() async {
        let store = HistoryStore(fileURL: tempURL())
        let now = Date()
        await store.record(snapshot(percent: 10, at: now))
        let later = now.addingTimeInterval(HistoryStore.heartbeatInterval + 1)
        #expect(await store.record(snapshot(percent: 10, at: later)))
        #expect(await store.rowCount() == 2)
    }

    @Test("One corrupt line does not lose the rest of the archive")
    func survivesCorruptLine() async throws {
        let url = tempURL()
        let store = HistoryStore(fileURL: url)
        let now = Date()
        await store.record(snapshot(percent: 10, at: now))

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{ truncated\n".utf8))
        try handle.close()

        await store.record(snapshot(percent: 20, at: now.addingTimeInterval(60)))

        let loaded = await store.load()
        #expect(loaded.count == 2)
        #expect(loaded.map { $0.limits.first?.percent } == [10, 20])
    }

    @Test("Reading a store that has never been written returns empty")
    func emptyStore() async {
        let store = HistoryStore(fileURL: tempURL())
        #expect(await store.load().isEmpty)
        #expect(await store.rowCount() == 0)
    }

    @Test("A limit applies to the tail, so charts get the newest rows")
    func limitTakesNewest() async {
        let store = HistoryStore(fileURL: tempURL())
        let now = Date()
        for index in 0..<5 {
            await store.record(snapshot(percent: index, at: now.addingTimeInterval(Double(index) * 60)))
        }
        let loaded = await store.load(limit: 2)
        #expect(loaded.map { $0.limits.first?.percent } == [3, 4])
    }
}
