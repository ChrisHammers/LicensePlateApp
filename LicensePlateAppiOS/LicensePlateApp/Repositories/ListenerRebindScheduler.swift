//
//  ListenerRebindScheduler.swift
//  LicensePlateApp
//
//  Bounded rebind-after-error for a Firestore snapshot listener.
//
//  Firestore terminates a listener once it has delivered an error (firebase-ios-sdk 12.14.0:
//  `EventManager::OnError` erases the query, `SyncEngine::RemoveAndCleanupTarget` drops the target),
//  yet the `ListenerRegistration` stays non-nil — so only the owning repository can bring the listen
//  back. The repository owns the listener and the rebind itself; this type owns the budget and the
//  clock, so the policy is pinned once for every repository that uses it.
//

import Foundation

@MainActor
final class ListenerRebindScheduler {

    /// Delay before each rebind attempt; the count is the bound. 31 s in total — long enough for a
    /// token / App Check round trip at a uid boundary, short enough that a persistently denied
    /// listen (a local-only identity) costs five denied reads per bind and then goes quiet.
    nonisolated static let defaultDelays: [TimeInterval] = [1, 2, 4, 8, 16]

    private let delays: [TimeInterval]
    private let sleep: (TimeInterval) async -> Void
    private var attemptsUsed = 0
    private var pending: Task<Void, Never>?

    init(
        delays: [TimeInterval] = ListenerRebindScheduler.defaultDelays,
        sleep: @escaping (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        self.delays = delays
        self.sleep = sleep
    }

    /// Schedules `rebind` after the next delay in the budget and returns that delay, or `nil` when
    /// the budget is spent — the caller then stays unbound until `reset()`.
    @discardableResult
    func scheduleRebind(_ rebind: @escaping @MainActor () -> Void) -> TimeInterval? {
        guard attemptsUsed < delays.count else { return nil }
        let delay = delays[attemptsUsed]
        attemptsUsed += 1
        pending?.cancel()
        pending = Task { [sleep] in
            await sleep(delay)
            guard !Task.isCancelled else { return }
            rebind()
        }
        return delay
    }

    /// Trace text for a `scheduleRebind` result, so every repository words the outcome alike.
    static func describe(_ delay: TimeInterval?) -> String {
        delay.map { "rebind in \(Int($0)) s" }
            ?? "rebind budget spent — no listener until the next startListening"
    }

    /// A server-confirmed snapshot proves the listen is healthy: the next failure gets a full
    /// budget. Deliberately NOT called for a from-cache snapshot — a warm cache answers before the
    /// server denies, and refilling on it would turn a persistent denial into an unbounded loop.
    func noteServerConfirmedSnapshot() {
        attemptsUsed = 0
    }

    /// Stop / uid change: drops the pending rebind and refills the budget.
    func reset() {
        pending?.cancel()
        pending = nil
        attemptsUsed = 0
    }
}
