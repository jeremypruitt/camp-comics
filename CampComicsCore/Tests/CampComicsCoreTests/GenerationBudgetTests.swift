import Foundation
import Testing
@testable import CampComicsCore

@Suite("GenerationBudget value math")
struct GenerationBudgetValueTests {

    @Test func emptyHasFullRemaining() {
        let budget = GenerationBudget.empty

        #expect(budget.spent == 0)
        #expect(budget.remaining == GenerationBudget.limit)
        #expect(budget.remaining == 32)
        #expect(budget.isExhausted == false)
    }

    @Test func decrementedAdvancesSpent() {
        let budget = GenerationBudget.empty

        let after = budget.decremented()

        #expect(after.spent == 1)
        #expect(after.remaining == 31)
        #expect(after.isExhausted == false)
    }

    @Test func remainingClampsAtZero() {
        let budget = GenerationBudget(spent: 100)

        #expect(budget.remaining == 0)
        #expect(budget.isExhausted)
    }

    @Test func isExhaustedFlipsAtLimit() {
        let justUnder = GenerationBudget(spent: GenerationBudget.limit - 1)
        let atLimit = GenerationBudget(spent: GenerationBudget.limit)

        #expect(justUnder.isExhausted == false)
        #expect(justUnder.remaining == 1)
        #expect(atLimit.isExhausted)
        #expect(atLimit.remaining == 0)
    }
}

@Suite("GenerationBudget persistence via PlayerStore")
struct GenerationBudgetStoreTests {

    private func makeStore() throws -> (PlayerStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("camp-comics-tests-\(UUID().uuidString)", isDirectory: true)
        let store = try PlayerStore(root: root)
        return (store, root)
    }

    @Test func freshPlayerHasEmptyBudgetWithoutFile() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")

        let budget = store.generationBudget(playerId: player.id)

        #expect(budget == GenerationBudget.empty)
        #expect(budget.remaining == 32)
        #expect(budget.isExhausted == false)
    }

    @Test func setThenGetRoundTrips() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")

        try store.setGenerationBudget(playerId: player.id, GenerationBudget(spent: 7))

        let budget = store.generationBudget(playerId: player.id)
        #expect(budget == GenerationBudget(spent: 7))
        #expect(budget.remaining == 25)
    }

    @Test func budgetsAreIsolatedPerPlayer() throws {
        let (store, _) = try makeStore()
        let a = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        let b = try store.create(playerName: "Bea", characterName: "", classKey: "druid")

        try store.setGenerationBudget(playerId: a.id, GenerationBudget(spent: 10))

        #expect(store.generationBudget(playerId: a.id).spent == 10)
        #expect(store.generationBudget(playerId: b.id) == GenerationBudget.empty)
        #expect(store.generationBudget(playerId: b.id).remaining == 32)
    }
}
