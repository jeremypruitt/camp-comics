import CampComicsCore

extension PanelRequirement: @retroactive Identifiable {
    public var id: String { "\(emotion.rawValue)|\(position.rawValue)" }
}
