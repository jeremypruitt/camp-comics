import Testing
@testable import CampComicsCore

@Suite("PromptCopyBook")
struct PromptCopyTests {

    @Test func neutralFrontHasFriendlyCoachingCopy() {
        let copy = PromptCopyBook.copy(for: PanelRequirement(emotion: .neutral, position: .front))
        #expect(copy.emoji == "🙂")
        #expect(copy.title == "Neutral, looking at me")
        #expect(copy.subtitle.contains("eye level"))
    }

    @Test func joyProfileHasSideProfileCopy() {
        let copy = PromptCopyBook.copy(for: PanelRequirement(emotion: .joy, position: .profile))
        #expect(copy.emoji == "😏")
        #expect(copy.title.lowercased().contains("profile"))
    }

    @Test func everyRequirementHasNonEmptyCopy() {
        for emotion in Emotion.allCases {
            for position in Position.allCases {
                let copy = PromptCopyBook.copy(for: PanelRequirement(emotion: emotion, position: position))
                #expect(!copy.emoji.isEmpty)
                #expect(!copy.title.isEmpty)
                #expect(!copy.subtitle.isEmpty)
            }
        }
    }
}
