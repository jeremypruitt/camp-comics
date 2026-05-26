import CampComicsCore
import Foundation

/// Loads class templates from the YAML files bundled under Templates/ in the
/// app resources. Templates/ is a symlink at the project source level pointing
/// at the repo-root templates/ folder so the iOS app and the legacy Python
/// pipeline share one canonical source of truth.
enum BundledTemplates {
    static let allClassKeys: [String] =
        ["druid", "warrior", "wizard", "bard", "healer", "trickster"]

    /// Loads the class-specific hero card PNG from Templates/refs/. Slot 2
    /// of every panel generation per ADR-0004 — costume + painted style
    /// anchor, faceless by design. Crashes if missing because the app can't
    /// generate panels without it; treated as a build-time invariant.
    static func heroCardData(forClassKey key: String) -> Data {
        guard let url = Bundle.main.url(forResource: "\(key)_hero",
                                        withExtension: "png",
                                        subdirectory: "Templates/refs")
                ?? Bundle.main.url(forResource: "\(key)_hero", withExtension: "png")
        else {
            fatalError("Missing bundled hero card for class '\(key)'.")
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            fatalError("Failed reading \(url.lastPathComponent): \(error)")
        }
    }

    static func template(forClassKey key: String) -> ClassTemplate {
        if let cached = cache[key] { return cached }

        guard let url = Bundle.main.url(forResource: key,
                                        withExtension: "yaml",
                                        subdirectory: "Templates")
                ?? Bundle.main.url(forResource: key, withExtension: "yaml")
        else {
            fatalError("Missing bundled YAML for class '\(key)'.")
        }

        let yaml: String
        do {
            yaml = try String(contentsOf: url, encoding: .utf8)
        } catch {
            fatalError("Failed reading \(url.lastPathComponent): \(error)")
        }

        let template: ClassTemplate
        do {
            template = try TemplateLoader.load(yaml: yaml)
        } catch {
            fatalError("Failed parsing \(url.lastPathComponent): \(error)")
        }

        cache[key] = template
        return template
    }

    private static var cache: [String: ClassTemplate] = [:]
}
