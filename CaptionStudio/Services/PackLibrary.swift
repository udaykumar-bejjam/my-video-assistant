import Foundation

/// Loads Shorts Pack recipes from AssetLibraries/packs (or bundled Resources/Libraries/packs).
@MainActor
final class PackLibrary: ObservableObject {
    @Published private(set) var packs: [ShortsPack] = []
    @Published private(set) var rootURL: URL?

    init() {
        reload()
    }

    func reload() {
        let root = Self.resolveLibrariesRoot()
        rootURL = root
        let url = root.appendingPathComponent("packs").appendingPathComponent("catalog.json")
        guard let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(ShortsPackCatalog.self, from: data)
        else {
            packs = Self.fallbackPacks
            return
        }
        packs = catalog.items
    }

    func pack(id: String?) -> ShortsPack? {
        guard let id else { return nil }
        return packs.first { $0.id == id }
    }

    private static func resolveLibrariesRoot() -> URL {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Libraries"),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("packs/catalog.json").path)
            || FileManager.default.fileExists(atPath: bundled.appendingPathComponent("pngs/catalog.json").path) {
            return bundled
        }
        let thisFile = URL(fileURLWithPath: #filePath)
        var dir = thisFile.deletingLastPathComponent()
        for _ in 0..<8 {
            let candidates = [
                dir.appendingPathComponent("Resources/Libraries"),
                dir.appendingPathComponent("AssetLibraries"),
                dir.appendingPathComponent("../AssetLibraries"),
                dir.appendingPathComponent("../../AssetLibraries")
            ]
            for candidate in candidates {
                let resolved = candidate.standardizedFileURL
                if FileManager.default.fileExists(atPath: resolved.appendingPathComponent("packs/catalog.json").path)
                    || FileManager.default.fileExists(atPath: resolved.appendingPathComponent("pngs/catalog.json").path) {
                    return resolved
                }
            }
            dir = dir.deletingLastPathComponent()
        }
        return Bundle.main.bundleURL
    }

    /// Built-in defaults if catalog is missing (previews / incomplete checkout).
    private static var fallbackPacks: [ShortsPack] {
        [
            ShortsPack(
                id: "hype",
                name: "Hype",
                subtitle: "Maximum energy & punch",
                systemImage: "flame.fill",
                aspect: "9:16",
                captionStyle: "upperPunch",
                effectBias: ["punch", "color-pulse", "stomp", "slam"],
                sfxBias: ["bass-hit", "riser", "whoosh"],
                gifTags: ["hype", "celebration"],
                wordHitsPerCaption: 1,
                requireHookInFirstSeconds: 3,
                gifDensity: "high",
                accentColor: "#FF2D2D"
            ),
            ShortsPack(
                id: "hook",
                name: "Hook",
                subtitle: "Stop the scroll in 3 seconds",
                systemImage: "bolt.fill",
                aspect: "9:16",
                captionStyle: "upperPunch",
                effectBias: ["punch", "slam", "stomp", "shake"],
                sfxBias: ["riser", "bass-hit", "whoosh"],
                gifTags: ["hype", "impact"],
                wordHitsPerCaption: 1,
                requireHookInFirstSeconds: 3,
                gifDensity: "high",
                accentColor: "#FFEF5A"
            )
        ]
    }
}
