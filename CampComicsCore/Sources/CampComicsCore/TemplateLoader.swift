import Foundation
import Yams

public enum TemplateLoaderError: Error, Equatable {
    case decoding(String)
    case missingCover
}

/// Parses a class template YAML (e.g. templates/druid.yaml) into a ClassTemplate.
///
/// The on-disk YAML is richer than ClassTemplate (palette, costume, fallbacks,
/// prompt overrides) — TemplateLoader keeps only what the capture-planning side
/// of the app cares about: the per-panel (emotion, position) plus the cover's
/// (emotion, position).
public enum TemplateLoader {

    public static func load(yaml: String) throws -> ClassTemplate {
        let decoder = YAMLDecoder()
        let dto: TemplateDTO
        do {
            dto = try decoder.decode(TemplateDTO.self, from: yaml)
        } catch {
            throw TemplateLoaderError.decoding(String(describing: error))
        }

        let panels = dto.panels.map { panel in
            PanelSpec(
                n: panel.n,
                beat: panel.caption ?? panel.scene ?? "",
                emotion: panel.emotion,
                position: panel.position
            )
        }
        let cover = PanelRequirement(emotion: dto.cover.emotion, position: dto.cover.position)

        return ClassTemplate(
            classKey: dto.classKey,
            name: dto.displayName ?? dto.classKey.capitalized,
            panels: panels,
            cover: cover
        )
    }
}

private struct TemplateDTO: Decodable {
    let classKey: String
    let displayName: String?
    let panels: [PanelDTO]
    let cover: CoverDTO

    enum CodingKeys: String, CodingKey {
        case classKey = "class"
        case displayName = "display_name"
        case panels
        case cover
    }
}

private struct PanelDTO: Decodable {
    let n: Int
    let emotion: Emotion
    let position: Position
    let scene: String?
    let caption: String?
}

private struct CoverDTO: Decodable {
    let emotion: Emotion
    let position: Position
}
