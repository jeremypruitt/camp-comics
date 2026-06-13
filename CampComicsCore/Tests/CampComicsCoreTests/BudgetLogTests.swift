import Foundation
import Testing
@testable import CampComicsCore

@Suite("BudgetLog")
struct BudgetLogTests {

    private func makeStore() throws -> (PlayerStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("camp-comics-tests-\(UUID().uuidString)", isDirectory: true)
        let store = try PlayerStore(root: root)
        return (store, root)
    }

    @Test func budgetLogIsEmptyWhenFileAbsent() throws {
        let (store, _) = try makeStore()
        #expect(store.budgetLog(playerId: "player_001").isEmpty)
    }

    @Test func appendThenReadRoundTripsAllFields() throws {
        let (store, _) = try makeStore()
        let when = Date(timeIntervalSince1970: 1_750_000_000)
        let entry = BudgetLogEntry(timestamp: when,
                                   event: .spend,
                                   reason: .reroll,
                                   target: "panel_07",
                                   spentAfter: 17,
                                   remainingAfter: 15,
                                   cost: 1)
        try store.appendBudgetLog(playerId: "player_001", entry)
        #expect(store.budgetLog(playerId: "player_001") == [entry])
    }

    @Test func appendGrowsAndPreservesOrderAcrossEvents() throws {
        let (store, _) = try makeStore()
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let spend = BudgetLogEntry(timestamp: base, event: .spend, reason: .initial,
                                   target: "panel_02", spentAfter: 3, remainingAfter: 29, cost: 1)
        let bounce = BudgetLogEntry(timestamp: base.addingTimeInterval(60), event: .bounce, reason: .reroll,
                                    target: "panel_02", spentAfter: 32, remainingAfter: 0, cost: 1)
        let friction = BudgetLogEntry(timestamp: base.addingTimeInterval(120), event: .friction, reason: .reroll,
                                      target: "panel_05", spentAfter: 20, remainingAfter: 12, cost: 3)
        try store.appendBudgetLog(playerId: "player_001", spend)
        try store.appendBudgetLog(playerId: "player_001", bounce)
        try store.appendBudgetLog(playerId: "player_001", friction)
        #expect(store.budgetLog(playerId: "player_001") == [spend, bounce, friction])
    }
}
