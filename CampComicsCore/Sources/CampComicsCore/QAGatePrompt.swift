import Foundation

public enum QAGatePrompt {
    public static func assemble(for template: ClassTemplate) -> String {
        "This person as a generic \(template.name) hero in painted Dungeons & Dragons 5th Edition sourcebook style, full body, cinematic lighting. "
        + "The character's face must match the reference photo exactly. "
        + "No text or letters in the image."
    }
}
