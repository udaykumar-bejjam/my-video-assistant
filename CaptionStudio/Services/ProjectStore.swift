import Foundation
import UniformTypeIdentifiers

/// Persists projects as JSON under Application Support/CaptionStudio/Projects/<id>/.
///
/// Each project folder:
/// - `project.json` — captions, overlays, SFX refs, audio mix, session (pretty JSON)
/// - `video.<ext>` — footage copy
///
/// Library media is referenced by id/filename (not copied). Index: `index.json`.
@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var drafts: [SavedProject] = []

    private let fileManager = FileManager.default
    private let indexFileName = "index.json"
    private let projectFileName = "project.json"

    /// Prefer new Projects path; still read legacy Drafts on first load.
    private var projectsRoot: URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let root = support.appendingPathComponent("CaptionStudio/Projects", isDirectory: true)
        if !fileManager.fileExists(atPath: root.path) {
            try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }

    private var legacyDraftsRoot: URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return support.appendingPathComponent("CaptionStudio/Drafts", isDirectory: true)
    }

    private var indexURL: URL {
        projectsRoot.appendingPathComponent(indexFileName)
    }

    private var encoder: JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }

    private var decoder: JSONDecoder {
        let dec = JSONDecoder()
        let isoFractional: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()
        let isoBasic: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()
        dec.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            // Legacy drafts used DeferredToDate (Double, reference date).
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: seconds)
            }
            let string = try container.decode(String.self)
            if let date = isoFractional.date(from: string) ?? isoBasic.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized date: \(string)"
            )
        }
        return dec
    }

    init() {
        migrateLegacyDraftsIfNeeded()
        reload()
    }

    func reload() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? decoder.decode([SavedProject].self, from: data)
        else {
            // Rebuild index by scanning folders if index is missing/corrupt.
            drafts = scanProjectFolders()
            if !drafts.isEmpty {
                try? persistIndex()
            }
            return
        }
        drafts = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func save(
        project: VideoProject,
        session: ProjectSessionState = .default,
        distribution: DistributionPackage? = nil
    ) throws -> SavedProject {
        guard let sourceURL = project.videoURL else {
            throw ProjectStoreError.noVideo
        }

        let folder = projectsRoot.appendingPathComponent(project.id.uuidString, isDirectory: true)
        if !fileManager.fileExists(atPath: folder.path) {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        let ext = sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension
        let videoName = "video.\(ext)"
        let destVideo = folder.appendingPathComponent(videoName)

        if destVideo.standardizedFileURL != sourceURL.standardizedFileURL {
            if fileManager.fileExists(atPath: destVideo.path) {
                try fileManager.removeItem(at: destVideo)
            }
            try fileManager.copyItem(at: sourceURL, to: destVideo)
        }

        var projectToSave = project
        projectToSave.videoURL = destVideo

        let saved = SavedProject.from(
            project: projectToSave,
            videoFileName: videoName,
            session: session,
            distribution: distribution
        )
        let projectURL = folder.appendingPathComponent(projectFileName)
        let encoded = try encoder.encode(saved)
        try encoded.write(to: projectURL, options: .atomic)

        var next = drafts.filter { $0.id != saved.id }
        next.insert(saved, at: 0)
        drafts = next
        try persistIndex()
        return saved
    }

    func load(id: UUID) throws -> (SavedProject, URL) {
        let folder = projectsRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        let projectURL = folder.appendingPathComponent(projectFileName)
        // Fall back to legacy Drafts path for older installs.
        let data: Data
        let videoBase: URL
        if fileManager.fileExists(atPath: projectURL.path) {
            data = try Data(contentsOf: projectURL)
            videoBase = folder
        } else {
            let legacy = legacyDraftsRoot.appendingPathComponent(id.uuidString, isDirectory: true)
            let legacyProject = legacy.appendingPathComponent(projectFileName)
            data = try Data(contentsOf: legacyProject)
            videoBase = legacy
        }
        let saved = try decoder.decode(SavedProject.self, from: data)
        let videoURL = videoBase.appendingPathComponent(saved.videoFileName)
        guard fileManager.fileExists(atPath: videoURL.path) else {
            throw ProjectStoreError.missingVideo
        }
        return (saved, videoURL)
    }

    func delete(id: UUID) throws {
        let folder = projectsRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        if fileManager.fileExists(atPath: folder.path) {
            try fileManager.removeItem(at: folder)
        }
        let legacy = legacyDraftsRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        if fileManager.fileExists(atPath: legacy.path) {
            try? fileManager.removeItem(at: legacy)
        }
        drafts.removeAll { $0.id == id }
        try persistIndex()
    }

    /// Export a portable package folder: `Name.captionstudio/project.json` + video.
    @discardableResult
    func exportPackage(id: UUID, to destinationFolder: URL) throws -> URL {
        let (saved, videoURL) = try load(id: id)
        let safeName = saved.title
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let packageName = (safeName.isEmpty ? "CaptionStudio" : safeName) + ".captionstudio"
        let package = destinationFolder.appendingPathComponent(packageName, isDirectory: true)
        if fileManager.fileExists(atPath: package.path) {
            try fileManager.removeItem(at: package)
        }
        try fileManager.createDirectory(at: package, withIntermediateDirectories: true)
        let destVideo = package.appendingPathComponent(saved.videoFileName)
        try fileManager.copyItem(at: videoURL, to: destVideo)
        let projectURL = package.appendingPathComponent(projectFileName)
        try encoder.encode(saved).write(to: projectURL, options: .atomic)
        return package
    }

    /// Import a portable `.captionstudio` package (or any folder with project.json + video).
    @discardableResult
    func importPackage(from packageURL: URL) throws -> SavedProject {
        let projectURL = packageURL.appendingPathComponent(projectFileName)
        guard fileManager.fileExists(atPath: projectURL.path) else {
            throw ProjectStoreError.invalidPackage
        }
        let data = try Data(contentsOf: projectURL)
        var saved = try decoder.decode(SavedProject.self, from: data)
        let sourceVideo = packageURL.appendingPathComponent(saved.videoFileName)
        guard fileManager.fileExists(atPath: sourceVideo.path) else {
            throw ProjectStoreError.missingVideo
        }

        // New id so import never overwrites an existing project silently.
        let newID = UUID()
        saved.id = newID
        saved.updatedAt = .now

        let folder = projectsRoot.appendingPathComponent(newID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let destVideo = folder.appendingPathComponent(saved.videoFileName)
        try fileManager.copyItem(at: sourceVideo, to: destVideo)
        try encoder.encode(saved).write(
            to: folder.appendingPathComponent(projectFileName),
            options: .atomic
        )

        var next = drafts.filter { $0.id != saved.id }
        next.insert(saved, at: 0)
        drafts = next
        try persistIndex()
        return saved
    }

    // MARK: - Private

    private func persistIndex() throws {
        let data = try encoder.encode(drafts)
        try data.write(to: indexURL, options: .atomic)
    }

    private func scanProjectFolders() -> [SavedProject] {
        let roots = [projectsRoot, legacyDraftsRoot]
        var found: [SavedProject] = []
        for root in roots {
            guard let kids = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for folder in kids where folder.hasDirectoryPath {
                let projectURL = folder.appendingPathComponent(projectFileName)
                guard let data = try? Data(contentsOf: projectURL),
                      let saved = try? decoder.decode(SavedProject.self, from: data)
                else { continue }
                found.append(saved)
            }
        }
        // Dedupe by id preferring newer updatedAt
        var byID: [UUID: SavedProject] = [:]
        for item in found {
            if let existing = byID[item.id] {
                if item.updatedAt > existing.updatedAt { byID[item.id] = item }
            } else {
                byID[item.id] = item
            }
        }
        return byID.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// One-time copy of legacy Drafts → Projects so older saves still appear.
    private func migrateLegacyDraftsIfNeeded() {
        let flag = projectsRoot.appendingPathComponent(".migrated-from-drafts")
        guard !fileManager.fileExists(atPath: flag.path),
              fileManager.fileExists(atPath: legacyDraftsRoot.path)
        else { return }

        if let kids = try? fileManager.contentsOfDirectory(
            at: legacyDraftsRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for folder in kids where folder.hasDirectoryPath {
                let dest = projectsRoot.appendingPathComponent(folder.lastPathComponent, isDirectory: true)
                if !fileManager.fileExists(atPath: dest.path) {
                    try? fileManager.copyItem(at: folder, to: dest)
                }
            }
            // Prefer reading legacy index into new index if projects index missing.
            let legacyIndex = legacyDraftsRoot.appendingPathComponent(indexFileName)
            if !fileManager.fileExists(atPath: indexURL.path),
               let data = try? Data(contentsOf: legacyIndex) {
                try? data.write(to: indexURL, options: .atomic)
            }
        }
        try? Data("ok".utf8).write(to: flag, options: .atomic)
    }
}

enum ProjectStoreError: LocalizedError {
    case noVideo
    case missingVideo
    case invalidPackage

    var errorDescription: String? {
        switch self {
        case .noVideo: return "Save a project that has an imported video."
        case .missingVideo: return "Project video file is missing."
        case .invalidPackage: return "Not a CaptionStudio project (missing project.json)."
        }
    }
}
