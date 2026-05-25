import CampComicsCore
import Foundation

/// Loads class templates from the YAML files bundled under Templates/ in the
/// app resources. Templates/ is a symlink at the project source level pointing
/// at the repo-root templates/ folder so the iOS app and the legacy Python
/// pipeline share one canonical source of truth.
enum BundledTemplates {
    static let allClassKeys: [String] =
        ["druid", "warrior", "wizard", "bard", "healer", "trickster"]

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
