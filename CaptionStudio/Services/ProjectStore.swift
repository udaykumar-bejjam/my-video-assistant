import Foundation
import UniformTypeIdentifiers

/// Persists drafts under Application Support/CaptionStudio/Drafts/<id>/.
@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var drafts: [SavedProject] = []

    private let fileManager = FileManager.default
    private let indexFileName = "index.json"
    private let projectFileName = "project.json"

    private var draftsRoot: URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let root = support.appendingPathComponent("CaptionStudio/Drafts", isDirectory: true)
        if !fileManager.fileExists(atPath: root.path) {
            try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }

    private var indexURL: URL {
        draftsRoot.appendingPathComponent(indexFileName)
    }

    init() {
        reload()
    }

    func reload() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([SavedProject].self, from: data)
        else {
            drafts = []
            return
        }
        drafts = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func save(project: VideoProject) throws -> SavedProject {
        guard let sourceURL = project.videoURL else {
            throw ProjectStoreError.noVideo
        }

        let folder = draftsRoot.appendingPathComponent(project.id.uuidString, isDirectory: true)
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

        let saved = SavedProject.from(project: projectToSave, videoFileName: videoName)
        let projectURL = folder.appendingPathComponent(projectFileName)
        let encoded = try JSONEncoder().encode(saved)
        try encoded.write(to: projectURL, options: .atomic)

        var next = drafts.filter { $0.id != saved.id }
        next.insert(saved, at: 0)
        drafts = next
        try persistIndex()
        return saved
    }

    func load(id: UUID) throws -> (SavedProject, URL) {
        let folder = draftsRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        let projectURL = folder.appendingPathComponent(projectFileName)
        let data = try Data(contentsOf: projectURL)
        let saved = try JSONDecoder().decode(SavedProject.self, from: data)
        let videoURL = folder.appendingPathComponent(saved.videoFileName)
        guard fileManager.fileExists(atPath: videoURL.path) else {
            throw ProjectStoreError.missingVideo
        }
        return (saved, videoURL)
    }

    func delete(id: UUID) throws {
        let folder = draftsRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        if fileManager.fileExists(atPath: folder.path) {
            try fileManager.removeItem(at: folder)
        }
        drafts.removeAll { $0.id == id }
        try persistIndex()
    }

    private func persistIndex() throws {
        let data = try JSONEncoder().encode(drafts)
        try data.write(to: indexURL, options: .atomic)
    }
}

enum ProjectStoreError: LocalizedError {
    case noVideo
    case missingVideo

    var errorDescription: String? {
        switch self {
        case .noVideo: return "Save a project that has an imported video."
        case .missingVideo: return "Draft video file is missing."
        }
    }
}
