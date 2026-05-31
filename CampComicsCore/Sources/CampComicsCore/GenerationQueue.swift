import Foundation

/// ADR-0009 Phase 2 producer. Adaptive K worker pool that pulls `PanelTarget`s
/// from a story-ordered FIFO and runs the caller-supplied `work` closure in
/// parallel. Adaptation rules:
/// - K starts at `initialK` (3 by default per ADR-0009), floor 1, ceiling 8.
/// - Any `PanelGeneratorError.throttled` decrements K by 1 and resets the
///   success streak.
/// - Five consecutive successes increment K by 1 and reset the streak.
/// - Per-session state — each new launch starts fresh at `initialK`.
///
/// Budget gating is delegated: `isExhausted` is polled before every pull. An
/// exhausted budget freezes new starts; in-flight work runs to completion.
///
/// **Failure handling** (Camp Comics invariant — see
/// `feedback-failures-never-penalize-user`): background failures are NOT a
/// user concern. The queue auto-retries any `.throttled` or non-cancellation
/// error in-place on the same target with exponential backoff, and only
/// emits `.failed` after `maxAttempts` true attempts. Subscribers see
/// `.throttled` for adaptive-K bookkeeping but should not treat it as
/// terminal — the same target keeps trying until success or hard cap.
public actor GenerationQueue {

    public enum Event: Sendable, Equatable {
        case completed(PanelTargetID)
        case throttled(PanelTargetID)
        /// Terminal failure after `maxAttempts` retries with exponential
        /// backoff. In normal operation, network blips + rate limits never
        /// reach this — only persistent failures (model safety blocks,
        /// long outages) do.
        case failed(PanelTargetID, String)
    }

    public static let defaultInitialK = 3
    public static let kFloor = 1
    public static let kCeiling = 8
    public static let successStreakForIncrement = 5
    /// Auto-retry policy. Backoff sequence in seconds for attempts 2..N:
    /// 2, 5, 10, 20, 30, 60. Attempt 1 is immediate; the queue emits
    /// `.failed` only after attempt 7 (last backoff = 60s, ~2.5 min total).
    public static let maxAttempts = 7
    public static let backoffSchedule: [UInt64] = [2, 5, 10, 20, 30, 60]

    private let pending: [PanelTarget]
    private var dispatchCursor: Int = 0
    private var emitCursor: Int = 0
    private var k: Int
    private var streak: Int = 0
    private let isExhausted: @Sendable () -> Bool
    private let work: @Sendable (PanelTarget) async throws -> Void
    /// Test seam: injected sleeper so retry backoff doesn't make tests slow.
    /// Production passes the real `Task.sleep(nanoseconds:)`.
    private let sleeper: @Sendable (UInt64) async -> Void

    private var continuation: AsyncStream<Event>.Continuation?
    private lazy var stream: AsyncStream<Event> = AsyncStream { c in
        self.continuation = c
    }
    /// Per-index outcome buffer. We dispatch concurrently but emit completions
    /// in story order so the review-stack head advances panel 2 → 3 → 4 even
    /// when panel 4 lands on disk first under K > 1.
    private var outcomes: [Event?] = []

    public init(targets: [PanelTarget],
                initialK: Int = GenerationQueue.defaultInitialK,
                isExhausted: @escaping @Sendable () -> Bool = { false },
                work: @escaping @Sendable (PanelTarget) async throws -> Void,
                sleeper: @escaping @Sendable (UInt64) async -> Void = { ns in
                    try? await Task.sleep(nanoseconds: ns)
                }) {
        self.pending = targets
        self.k = max(Self.kFloor, min(Self.kCeiling, initialK))
        self.isExhausted = isExhausted
        self.work = work
        self.sleeper = sleeper
        self.outcomes = Array(repeating: nil, count: targets.count)
    }

    public var currentConcurrency: Int { k }

    public var events: AsyncStream<Event> {
        _ = stream
        return stream
    }

    public func run() async {
        await withTaskGroup(of: Void.self) { group in
            // Seed up to K workers. Each worker pulls the next index and
            // recurses inside the task by calling `pullNext()` again until the
            // queue empties or the budget gate freezes pulls.
            var seeded = 0
            while seeded < k, let index = nextPullableIndex() {
                seeded += 1
                let target = pending[index]
                group.addTask { [weak self] in
                    await self?.process(index: index, target: target, group: nil)
                }
            }
            await group.waitForAll()
        }
        continuation?.finish()
    }

    private func nextPullableIndex() -> Int? {
        guard !isExhausted() else { return nil }
        guard dispatchCursor < pending.count else { return nil }
        let i = dispatchCursor
        dispatchCursor += 1
        return i
    }

    /// Runs one target to terminal disposition (either `.completed` or
    /// `.failed` after `maxAttempts`). Network/throttle errors are auto-
    /// retried with exponential backoff inside this same task — they never
    /// surface as terminal `.failed` to subscribers unless the target has
    /// genuinely exhausted retries. `.throttled` events are emitted as
    /// observability for adaptive-K, but the queue still retries the same
    /// target underneath.
    private func process(index: Int, target: PanelTarget,
                         group: TaskGroup<Void>?) async {
        var attempt = 1
        var lastError: String = ""
        while attempt <= Self.maxAttempts {
            do {
                try await work(target)
                record(.completed(target.id), at: index)
                break
            } catch is CancellationError {
                return
            } catch PanelGeneratorError.throttled {
                // Emit observability for the adaptive-K bookkeeping path.
                // Same target keeps trying after backoff.
                yieldObservability(.throttled(target.id))
                applyAdaptation(for: .throttled(target.id))
                lastError = "throttled"
            } catch {
                lastError = String(describing: error)
            }
            if attempt == Self.maxAttempts {
                record(.failed(target.id, lastError), at: index)
                break
            }
            let backoffSeconds = Self.backoffSchedule[min(attempt - 1, Self.backoffSchedule.count - 1)]
            await sleeper(backoffSeconds * 1_000_000_000)
            attempt += 1
        }
        // After one target reaches terminal disposition, dispatch the next
        // pullable item from this same task so the actor never drops below K
        // active workers while there's still queue + budget left.
        while let next = nextPullableIndex() {
            await process(index: next, target: pending[next], group: group)
            return
        }
    }

    /// Like `record` but for non-terminal observability events — does NOT
    /// write to the outcomes buffer (so `flushOrderedEmissions` doesn't
    /// advance past an unfinished target) and emits immediately rather than
    /// waiting for story order.
    private func yieldObservability(_ event: Event) {
        continuation?.yield(event)
    }

    private func record(_ event: Event, at index: Int) {
        outcomes[index] = event
        applyAdaptation(for: event)
        flushOrderedEmissions()
    }

    private func flushOrderedEmissions() {
        while emitCursor < outcomes.count, let event = outcomes[emitCursor] {
            continuation?.yield(event)
            emitCursor += 1
        }
    }

    private func applyAdaptation(for event: Event) {
        switch event {
        case .throttled:
            k = max(Self.kFloor, k - 1)
            streak = 0
        case .completed:
            streak += 1
            if streak >= Self.successStreakForIncrement {
                k = min(Self.kCeiling, k + 1)
                streak = 0
            }
        case .failed:
            streak = 0
        }
    }
}
