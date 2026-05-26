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
                scene: panel.scene ?? "",
                composition: panel.composition ?? "",
                costumeOverride: panel.costumeOverride,
                styleOverride: panel.styleOverride,
                referencePanel: panel.referencePanel.flatMap(Int.init),
                emotion: panel.emotion,
                position: panel.position
            )
        }
        let cover = PanelRequirement(emotion: dto.cover.emotion, position: dto.cover.position)
        let palette = Palette(
            lighting: dto.palette?.lighting ?? "",
            colors: dto.palette?.colors ?? ""
        )

        return ClassTemplate(
            classKey: dto.classKey,
            name: dto.displayName ?? dto.classKey.capitalized,
            costume: dto.costume ?? "",
            palette: palette,
            panels: panels,
            cover: cover
        )
    }
}

private struct TemplateDTO: Decodable {
    let classKey: String
    let displayName: String?
    let costume: String?
    let palette: PaletteDTO?
    let panels: [PanelDTO]
    let cover: CoverDTO

    enum CodingKeys: String, CodingKey {
        case classKey = "class"
        case displayName = "display_name"
        case costume
        case palette
        case panels
        case cover
    }
}

private struct PaletteDTO: Decodable {
    let lighting: String
    let colors: String
}

private struct PanelDTO: Decodable {
    let n: Int
    let emotion: Emotion
    let position: Position
    let scene: String?
    let composition: String?
    let caption: String?
    let costumeOverride: String?
    let styleOverride: String?
    /// Stored quoted + zero-padded ("01") in legacy YAML so the legacy
    /// generate.py can pattern-match `panel_NN.png`. iOS converts to Int.
    let referencePanel: String?

    enum CodingKeys: String, CodingKey {
        case n, emotion, position, scene, composition, caption
        case costumeOverride = "costume_override"
        case styleOverride = "style_override"
        case referencePanel = "reference_panel"
    }
}

private struct CoverDTO: Decodable {
    let emotion: Emotion
    let position: Position
}
