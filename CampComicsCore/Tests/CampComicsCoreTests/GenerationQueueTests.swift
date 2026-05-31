import Foundation
import Testing
@testable import CampComicsCore

@Suite("GenerationQueue")
struct GenerationQueueTests {

    // MARK: - Test fixtures

    private func target(_ n: Int) -> PanelTarget {
        .panel(n: n, spec: PanelSpec(n: n, beat: "b", emotion: .neutral, position: .front))
    }

    private var coverTarget: PanelTarget {
        .cover(spec: CoverSpec(emotion: .neutral, position: .front, poseDirective: "p"))
    }

    @Test func startingConcurrencyIsThree() async {
        let queue = GenerationQueue(targets: [target(2)],
                                    initialK: 3,
                                    isExhausted: { false },
                                    work: { _ in })

        let k = await queue.currentConcurrency

        #expect(k == 3)
    }

    @Test func fiveConsecutiveSuccessesIncrementKByOne() async throws {
        // K starts at 3; after the 5th success it should bump to 4.
        let targets = (2...6).map(target)
        let queue = GenerationQueue(targets: targets,
                                    initialK: 3,
                                    isExhausted: { false },
                                    work: { _ in })

        _ = try await collectAll(queue: queue)

        let k = await queue.currentConcurrency
        #expect(k == 4)
    }

    @Test func successStreakResetsAfterAThrottle() async throws {
        // Pattern: throttle, success × 4. Started at K=2; the throttle resets
        // the streak to 0 and drops K to 1; the trailing 4 successes don't form
        // a fresh streak of 5, so K stays at 1. K=1 keeps dispatch sequential
        // so streak accounting is deterministic.
        let targets = (2...6).map(target)
        let queue = GenerationQueue(
            targets: targets,
            initialK: 2,
            isExhausted: { false },
            work: { t in
                if case .panel(2, _) = t {
                    throw PanelGeneratorError.throttled(retryAfterSeconds: nil)
                }
            }
        )

        _ = try await collectAll(queue: queue)

        let k = await queue.currentConcurrency
        #expect(k == 1)
    }

    @Test func exhaustedBudgetStopsNewPulls() async throws {
        // After 3 completions the budget flips exhausted; the remaining 7
        // targets must never run.
        let targets = (2...11).map(target)
        let completedCount = Counter()
        let queue = GenerationQueue(
            targets: targets,
            initialK: 1,
            isExhausted: { completedCount.value >= 3 },
            work: { _ in completedCount.increment() }
        )

        let collected = try await collectAll(queue: queue)

        #expect(collected.count == 3)
        #expect(collected == [.completed(.panel(2)),
                              .completed(.panel(3)),
                              .completed(.panel(4))])
    }

    @Test func kNeverFallsBelowOne() async throws {
        // Repeated 429s on a long queue must clamp K at the floor, not run it
        // negative and freeze dispatch.
        let targets = (2...10).map(target)
        let queue = GenerationQueue(targets: targets,
                                    initialK: 3,
                                    isExhausted: { false },
                                    work: { _ in
            throw PanelGeneratorError.throttled(retryAfterSeconds: nil)
        })

        _ = try await collectAll(queue: queue)

        let k = await queue.currentConcurrency
        #expect(k == 1)
    }

    @Test func kNeverExceedsCeilingOfEight() async throws {
        // 50 straight successes at K=8 should never overshoot the ADR-0009
        // ceiling of 8.
        let targets = (1...50).map(target)
        let queue = GenerationQueue(targets: targets,
                                    initialK: 8,
                                    isExhausted: { false },
                                    work: { _ in })

        _ = try await collectAll(queue: queue)

        let k = await queue.currentConcurrency
        #expect(k == 8)
    }

    @Test func throttledResponseDecrementsKByOne() async throws {
        let targets = [target(2)]
        let queue = GenerationQueue(targets: targets,
                                    initialK: 3,
                                    isExhausted: { false },
                                    work: { _ in
            throw PanelGeneratorError.throttled(retryAfterSeconds: nil)
        })

        let collected = try await collectAll(queue: queue)

        #expect(collected == [.throttled(.panel(2))])
        let k = await queue.currentConcurrency
        #expect(k == 2)
    }

    @Test func dispatchesAllTargetsAndEmitsCompletionInStoryOrder() async throws {
        // The worker pool is allowed to start panels concurrently and finish out
        // of order, but the queue exposes story-ordered completions so the head
        // of the review stack stays panel 2 → 3 → 4 even if 4 lands on disk first.
        let targets: [PanelTarget] = [target(2), target(3), target(4)]
        let queue = GenerationQueue(targets: targets,
                                    initialK: 1,
                                    isExhausted: { false },
                                    work: { _ in })

        let collected = try await collectAll(queue: queue)

        #expect(collected == [.completed(.panel(2)),
                              .completed(.panel(3)),
                              .completed(.panel(4))])
    }

    // Thread-safe counter for the exhaustion test — `isExhausted` is called
    // from the actor, `increment()` from the worker closure body. Two callers,
    // one shared mutable int.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: Int = 0
        var value: Int { lock.lock(); defer { lock.unlock() }; return _value }
        func increment() { lock.lock(); _value += 1; lock.unlock() }
    }

    // MARK: - Helpers

    /// Run the queue to completion and collect every event in emission order.
    private func collectAll(queue: GenerationQueue) async throws -> [GenerationQueue.Event] {
        let stream = await queue.events
        async let drained: [GenerationQueue.Event] = {
            var out: [GenerationQueue.Event] = []
            for await event in stream { out.append(event) }
            return out
        }()
        await queue.run()
        return await drained
    }
}
