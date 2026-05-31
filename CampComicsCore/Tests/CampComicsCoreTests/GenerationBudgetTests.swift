import Foundation
import Testing
@testable import CampComicsCore

@Suite("GenerationBudget value math")
struct GenerationBudgetValueTests {

    @Test func emptyFor15PanelTemplateYields32Limit() {
        let budget = GenerationBudget.empty(panelCount: 15)

        #expect(budget.spent == 0)
        #expect(budget.limit == 32)
        #expect(budget.remaining == 32)
        #expect(budget.isExhausted == false)
    }

    @Test func emptyForSyntheticShortTemplateScales() {
        let budget = GenerationBudget.empty(panelCount: 5)

        #expect(budget.limit == 12)
        #expect(budget.remaining == 12)
    }

    @Test func decrementedAdvancesSpent() {
        let budget = GenerationBudget.empty(panelCount: 15)

        let after = budget.decremented()

        #expect(after.spent == 1)
        #expect(after.limit == 32)
        #expect(after.remaining == 31)
        #expect(after.isExhausted == false)
    }

    @Test func remainingClampsAtZero() {
        let budget = GenerationBudget(spent: 100, panelCount: 15)

        #expect(budget.remaining == 0)
        #expect(budget.isExhausted)
    }

    @Test func isExhaustedFlipsAtLimit() {
        let justUnder = GenerationBudget(spent: 31, panelCount: 15)
        let atLimit = GenerationBudget(spent: 32, panelCount: 15)

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

        let budget = store.generationBudget(playerId: player.id, panelCount: 15)

        #expect(budget == GenerationBudget.empty(panelCount: 15))
        #expect(budget.remaining == 32)
        #expect(budget.isExhausted == false)
    }

    @Test func setThenGetRoundTrips() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")

        try store.setGenerationBudget(playerId: player.id,
                                      GenerationBudget(spent: 7, panelCount: 15))

        let budget = store.generationBudget(playerId: player.id, panelCount: 15)
        #expect(budget == GenerationBudget(spent: 7, panelCount: 15))
        #expect(budget.remaining == 25)
    }

    @Test func budgetsAreIsolatedPerPlayer() throws {
        let (store, _) = try makeStore()
        let a = try store.create(playerName: "Alex", characterName: "", classKey: "druid")
        let b = try store.create(playerName: "Bea", characterName: "", classKey: "druid")

        try store.setGenerationBudget(playerId: a.id,
                                      GenerationBudget(spent: 10, panelCount: 15))

        #expect(store.generationBudget(playerId: a.id, panelCount: 15).spent == 10)
        #expect(store.generationBudget(playerId: b.id, panelCount: 15) == GenerationBudget.empty(panelCount: 15))
        #expect(store.generationBudget(playerId: b.id, panelCount: 15).remaining == 32)
    }

    @Test func limitFollowsTemplatePanelCountOnLoad() throws {
        let (store, _) = try makeStore()
        let player = try store.create(playerName: "Alex", characterName: "", classKey: "druid")

        try store.setGenerationBudget(playerId: player.id,
                                      GenerationBudget(spent: 3, panelCount: 5))

        let reloaded = store.generationBudget(playerId: player.id, panelCount: 5)
        #expect(reloaded.spent == 3)
        #expect(reloaded.limit == 12)
        #expect(reloaded.remaining == 9)
    }
}
