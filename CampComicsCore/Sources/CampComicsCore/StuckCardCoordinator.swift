import Foundation

/// Slice Q (#98). Pipes `GenerationQueue.Event` notifications into the
/// `PlayerStore` so terminal failures persist a `.failed` sentinel — the only
/// thing that turns a card into a stuck card on the deck. The queue's auto-
/// retry policy (PR #91) already drained 7 attempts of exponential backoff
/// before emitting `.failed`, so by the time we see one here the target is
/// genuinely stuck.
///
/// Throttles + completions are ignored. A throttle is observability for the
/// adaptive-K bookkeeping path; the same target keeps trying underneath. Auto-
/// deferring on throttle would penalize the operator for a transient network
/// blip — the opposite of the Camp Comics failure invariant.
public struct StuckCardCoordinator: Sendable {
    private let playerId: String
    private let store: PlayerStore

    public init(playerId: String, store: PlayerStore) {
        self.playerId = playerId
        self.store = store
    }

    public func handle(event: GenerationQueue.Event) {
        switch event {
        case .failed(let id, _):
            try? store.markDeferred(playerId: playerId, target: id)
        case .completed, .throttled:
            return
        }
    }
}
