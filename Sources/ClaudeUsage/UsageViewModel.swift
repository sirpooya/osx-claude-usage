import Foundation
import Observation
import ClaudeUsageCore

/// Drives one polling loop and holds everything the UI renders.
@MainActor
@Observable
final class UsageViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var snapshot: UsageSnapshot?
    private(set) var state: LoadState = .idle
    private(set) var lastSuccessAt: Date?
    private(set) var nextPollAt: Date?
    private(set) var historyRowCount: Int = 0

    private let client: UsageClient
    private let keychain: KeychainTokenStore
    private let history: HistoryStore
    private var policy = PollPolicy()
    private var loopTask: Task<Void, Never>?
    /// Set when a manual refresh should cut a scheduled sleep short.
    private var wakeUp: CheckedContinuation<Void, Never>?

    init(
        client: UsageClient = UsageClient(),
        keychain: KeychainTokenStore = KeychainTokenStore(),
        history: HistoryStore = HistoryStore()
    ) {
        self.client = client
        self.keychain = keychain
        self.history = history
    }

    var historyFileURL: URL {
        get async { await history.url }
    }

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        resumeSleep()
    }

    /// Refresh now, without waiting out the current interval.
    func refreshNow() {
        // A manual refresh should not be punished by an in flight backoff, but
        // the 30s floor still applies, enforced by nextInterval().
        policy.retryAfter = nil
        resumeSleep()
    }

    private func resumeSleep() {
        guard let continuation = wakeUp else { return }
        wakeUp = nil
        continuation.resume()
    }

    private func runLoop() async {
        while !Task.isCancelled {
            await pollOnce()

            let interval = policy.nextInterval()
            // Jitter keeps many installs from synchronizing onto the endpoint.
            let jitter = Double.random(in: 0...min(5, interval * 0.1))
            let wait = interval + jitter
            nextPollAt = Date().addingTimeInterval(wait)

            await sleep(for: wait)
        }
    }

    /// Sleeps, but returns early if refreshNow() fires.
    private func sleep(for seconds: TimeInterval) async {
        let timer = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            wakeUp = continuation
            Task {
                await timer.value
                self.resumeSleep()
            }
        }
        timer.cancel()
    }

    private func pollOnce() async {
        if snapshot == nil { state = .loading }

        do {
            // Read the keychain on every poll. Claude Code rotates this item
            // roughly hourly, so a cached token goes stale silently.
            let credentials = try keychain.readCredentials()
            let fresh = try await client.fetch(accessToken: credentials.accessToken)

            let changed = fresh.differsMeaningfully(from: snapshot)
            snapshot = fresh
            lastSuccessAt = fresh.fetchedAt
            state = .loaded
            policy.recordSuccess(changed: changed, at: fresh.fetchedAt)

            await history.record(fresh)
            historyRowCount = await history.rowCount()
        } catch {
            policy.recordFailure(error)
            state = .failed(error.localizedDescription)
        }
    }
}
