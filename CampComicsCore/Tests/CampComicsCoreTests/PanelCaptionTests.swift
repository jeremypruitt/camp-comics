import Testing
@testable import CampComicsCore

struct PanelCaptionTests {

    @Test func substitutesCamperNameToken() {
        let out = PanelCaption.substitute(
            "Hello {camper_name}, ready?",
            playerName: "Quinn")
        #expect(out == "Hello Quinn, ready?")
    }

    @Test func leavesCaptionUnchangedWhenNoToken() {
        let out = PanelCaption.substitute(
            "It was Tuesday. Nothing interesting was happening. Yet.",
            playerName: "Quinn")
        #expect(out == "It was Tuesday. Nothing interesting was happening. Yet.")
    }

    @Test func substitutesEveryOccurrence() {
        let out = PanelCaption.substitute(
            "{camper_name} looked at {camper_name}'s shadow.",
            playerName: "Mira")
        #expect(out == "Mira looked at Mira's shadow.")
    }
}
