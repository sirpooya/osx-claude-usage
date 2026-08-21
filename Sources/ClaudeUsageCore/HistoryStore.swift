import Foundation

/// Append only local history of every snapshot worth keeping.
///
/// The endpoint reports only the present moment, so without this there are no
/// trends and no burn rate at all. One JSON object per line, so a partial
/// write from a crash costs one row rather than the whole file.
public actor HistoryStore {
    /// Identical rows every 60s forever is noise, but long quiet stretches
    /// still need anchor points or a chart cannot draw a flat line. So write
    /// on any change, and otherwise at most once per heartbeat.
    public static let heartbeatInterval: TimeInterval = 10 * 60

    private let fileURL: URL
    private var lastWritten: UsageSnapshot?
    private var lastWriteAt: Date?

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("ClaudeUsage", isDirectory: true)
            .appendingPathComponent("history.jsonl", isDirectory: false)
    }

    public var url: URL { fileURL }

    /// Returns true when the snapshot was written.
    @discardableResult
    public func record(_ snapshot: UsageSnapshot) -> Bool {
        let changed = snapshot.differsMeaningfully(from: lastWritten)
        let stale = lastWriteAt.map { snapshot.fetchedAt.timeIntervalSince($0) >= Self.heartbeatInterval } ?? true
        guard changed || stale else { return false }

        guard let line = try? ISO8601.makeEncoder().encode(snapshot) else { return false }
        var payload = line
        payload.append(0x0A)

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: payload)
            } else {
                try payload.write(to: fileURL, options: .atomic)
            }
        } catch {
            return false
        }

        lastWritten = snapshot
        lastWriteAt = snapshot.fetchedAt
        return true
    }

    /// Reads history back, newest last. Malformed lines are skipped rather
    /// than aborting the read, so one bad row cannot lose the whole archive.
    public func load(limit: Int? = nil) -> [UsageSnapshot] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = ISO8601.makeDecoder()
        var results: [UsageSnapshot] = []
        for line in data.split(separator: 0x0A) where !line.isEmpty {
            if let snapshot = try? decoder.decode(UsageSnapshot.self, from: Data(line)) {
                results.append(snapshot)
            }
        }
        if let limit, results.count > limit {
            return Array(results.suffix(limit))
        }
        return results
    }

    public func rowCount() -> Int {
        guard let data = try? Data(contentsOf: fileURL) else { return 0 }
        return data.split(separator: 0x0A).filter { !$0.isEmpty }.count
    }
}
