import Foundation

/// Discriminator-only identity for a panel slot or the cover. Carries no spec
/// payload, so it's safe to embed in persisted records (`PanelAttempt`) and to
/// pass into `PlayerStore` operations that only need the disk address. The
/// `PanelTarget` enum widens this with the spec payload for generation paths.
public enum PanelTargetID: Hashable, Sendable, Codable {
    case panel(Int)
    case cover

    /// On-disk stem (no extension). Maps directly to:
    ///   .panel(7)  → panels/panel_07.png   / _candidates/panel_07/
    ///   .cover     → panels/cover.png      / _candidates/cover/
    public var diskName: String {
        switch self {
        case .panel(let n): return String(format: "panel_%02d", n)
        case .cover: return "cover"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if raw == "cover" {
            self = .cover
        } else if raw.hasPrefix("panel_"), let n = Int(raw.dropFirst("panel_".count)) {
            self = .panel(n)
        } else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unknown PanelTargetID discriminator: \(raw)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(diskName)
    }
}

/// Unified identity for the review surface (slice 11b). A `PanelTarget` carries
/// enough context to generate, persist, and render either a numbered panel slot
/// or the cover from one code path. The cover is a sibling artifact — not
/// "panel 13" — per CONTEXT.md, so it gets its own case rather than reusing the
/// panel branch with a magic n.
public enum PanelTarget: Equatable, Sendable {
    case panel(n: Int, spec: PanelSpec)
    case cover(spec: CoverSpec)

    public var id: PanelTargetID {
        switch self {
        case .panel(let n, _): return .panel(n)
        case .cover: return .cover
        }
    }

    public var diskName: String { id.diskName }

    public var requirement: PanelRequirement {
        switch self {
        case .panel(_, let spec): return spec.requirement
        case .cover(let spec): return spec.requirement
        }
    }
}
