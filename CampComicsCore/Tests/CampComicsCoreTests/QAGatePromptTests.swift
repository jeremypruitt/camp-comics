import Testing
@testable import CampComicsCore

@Suite("QAGatePrompt")
struct QAGatePromptTests {

    private static let druid = ClassTemplate(
        classKey: "druid",
        name: "Druid",
        panels: [],
        cover: CoverSpec(emotion: .neutral, position: .profile)
    )

    @Test func promptMentionsClassDisplayName() {
        let prompt = QAGatePrompt.assemble(for: Self.druid)
        #expect(prompt.contains("Druid"))
    }

    @Test func promptInvokesDungeonsAndDragonsStyle() {
        let prompt = QAGatePrompt.assemble(for: Self.druid)
        #expect(prompt.contains("Dungeons & Dragons"))
        #expect(prompt.contains("5th Edition"))
    }

    @Test func promptRequiresFaceMatch() {
        let prompt = QAGatePrompt.assemble(for: Self.druid)
        let lower = prompt.lowercased()
        #expect(lower.contains("face"))
        #expect(lower.contains("match"))
        #expect(lower.contains("reference photo"))
    }

    @Test func promptForbidsStrayLetteringInTheImage() {
        let prompt = QAGatePrompt.assemble(for: Self.druid)
        let lower = prompt.lowercased()
        #expect(lower.contains("no text"))
        #expect(lower.contains("letters"))
    }

    @Test func promptIsDeterministicAcrossCalls() {
        let first = QAGatePrompt.assemble(for: Self.druid)
        let second = QAGatePrompt.assemble(for: Self.druid)
        #expect(first == second)
    }
}
