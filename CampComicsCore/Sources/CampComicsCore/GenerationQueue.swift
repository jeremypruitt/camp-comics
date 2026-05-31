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
public actor GenerationQueue {

    public enum Event: Sendable, Equatable {
        case completed(PanelTargetID)
        case throttled(PanelTargetID)
        case failed(PanelTargetID, String)
    }

    public static let defaultInitialK = 3
    public static let kFloor = 1
    public static let kCeiling = 8
    public static let successStreakForIncrement = 5

    private let pending: [PanelTarget]
    private var dispatchCursor: Int = 0
    private var emitCursor: Int = 0
    private var k: Int
    private var streak: Int = 0
    private let isExhausted: @Sendable () -> Bool
    private let work: @Sendable (PanelTarget) async throws -> Void

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
                work: @escaping @Sendable (PanelTarget) async throws -> Void) {
        self.pending = targets
        self.k = max(Self.kFloor, min(Self.kCeiling, initialK))
        self.isExhausted = isExhausted
        self.work = work
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

    private func process(index: Int, target: PanelTarget,
                         group: TaskGroup<Void>?) async {
        let event: Event
        do {
            try await work(target)
            event = .completed(target.id)
        } catch PanelGeneratorError.throttled {
            event = .throttled(target.id)
        } catch {
            event = .failed(target.id, String(describing: error))
        }
        record(event, at: index)
        // After one work item finishes, dispatch the next pullable item from
        // this same task so the actor never drops below K active workers when
        // there's still queue + budget left.
        while let next = nextPullableIndex() {
            await process(index: next, target: pending[next], group: group)
            return
        }
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
