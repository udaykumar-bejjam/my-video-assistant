import Foundation

/// Loads bundled AssetLibraries catalogs (text / gif / png / sfx).
@MainActor
final class MediaLibraryStore: ObservableObject {
    @Published private(set) var catalogs: [MediaLibraryKind: MediaLibraryCatalog] = [:]
    @Published private(set) var rootURL: URL?

    init() {
        reload()
    }

    func reload() {
        var loaded: [MediaLibraryKind: MediaLibraryCatalog] = [:]
        let root = Self.resolveLibrariesRoot()
        rootURL = root

        for kind in MediaLibraryKind.allCases {
            let url = root.appendingPathComponent(kind.folderName).appendingPathComponent("catalog.json")
            guard let data = try? Data(contentsOf: url),
                  let catalog = try? JSONDecoder().decode(MediaLibraryCatalog.self, from: data)
            else { continue }
            loaded[kind] = catalog
        }
        catalogs = loaded
    }

    func items(for kind: MediaLibraryKind) -> [MediaLibraryItem] {
        catalogs[kind]?.items ?? []
    }

    func item(kind: MediaLibraryKind, id: String) -> MediaLibraryItem? {
        items(for: kind).first { $0.id == id }
    }

    func fileURL(kind: MediaLibraryKind, fileName: String) -> URL? {
        guard let root = rootURL else { return nil }
        let url = root.appendingPathComponent(kind.folderName).appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func resolveLibrariesRoot() -> URL {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Libraries"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        // Dev / preview: walk up from #file toward AssetLibraries or Resources/Libraries
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
                if FileManager.default.fileExists(atPath: resolved.appendingPathComponent("pngs/catalog.json").path) {
                    return resolved
                }
            }
            dir = dir.deletingLastPathComponent()
        }
        return Bundle.main.bundleURL
    }
}
