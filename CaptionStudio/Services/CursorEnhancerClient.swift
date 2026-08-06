import Foundation

enum EnhancerError: LocalizedError {
    case badURL
    case server(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .badURL: return "Enhancer URL is invalid."
        case .server(let m): return m
        case .decoding: return "Could not decode enhancement plan."
        }
    }
}

/// Talks to the local CaptionStudio enhancer (`@cursor/sdk` → composer-2.5).
@MainActor
final class CursorEnhancerClient: ObservableObject {
    @Published var baseURL: URL
    @Published var lastNote: String?
    @Published var isHealthy = false
    @Published var usesCursorKey = false

    init(baseURL: URL = URL(string: "http://127.0.0.1:8787")!) {
        self.baseURL = baseURL
    }

    func checkHealth() async {
        do {
            let url = baseURL.appendingPathComponent("health")
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                isHealthy = (json["ok"] as? Bool) == true
                usesCursorKey = (json["hasCursorKey"] as? Bool) == true
                lastNote = usesCursorKey
                    ? "Cursor SDK connected (composer-2.5)"
                    : "Enhancer online — heuristic mode (set CURSOR_API_KEY)"
            }
        } catch {
            isHealthy = false
            usesCursorKey = false
            lastNote = "Enhancer offline at \(baseURL.absoluteString)"
        }
    }

    func enhance(
        captions: [CaptionSegment],
        duration: TimeInterval,
        forceHeuristic: Bool = false
    ) async throws -> EnhancementPlan {
        let url = baseURL.appendingPathComponent("enhance")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "duration": duration,
            "forceHeuristic": forceHeuristic,
            "captions": captions.map { [
                "text": $0.text,
                "startTime": $0.startTime,
                "endTime": $0.endTime
            ] as [String: Any] }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw EnhancerError.server(message ?? "HTTP \(http.statusCode)")
        }

        do {
            let plan = try JSONDecoder().decode(EnhancementPlan.self, from: data)
            lastNote = plan.note ?? plan.summary
            return plan
        } catch {
            throw EnhancerError.decoding
        }
    }

    /// Offline path used when the Node enhancer isn't running.
    func localHeuristicPlan(
        captions: [CaptionSegment],
        duration: TimeInterval,
        libraries: MediaLibraryStore
    ) -> EnhancementPlan {
        var placements: [EnhancementPlacement] = []
        let texts = libraries.items(for: .textStyles)
        let gifs = libraries.items(for: .gifs)
        let pngs = libraries.items(for: .pngs)
        let sfx = libraries.items(for: .sfx)

        for (index, caption) in captions.prefix(8).enumerated() {
            if let text = texts[safe: index % max(texts.count, 1)] {
                placements.append(
                    EnhancementPlacement(
                        kind: "text",
                        assetId: text.id,
                        startTime: caption.startTime,
                        endTime: min(caption.endTime, caption.startTime + (text.defaultDuration ?? 1.8)),
                        x: 0.5,
                        y: 0.28,
                        scale: 1,
                        rotation: index.isMultiple(of: 2) ? -2 : 3,
                        text: caption.text.split(separator: " ").prefix(4).joined(separator: " "),
                        reason: "Local stylish text"
                    )
                )
            }
            if index.isMultiple(of: 2), let gif = gifs[safe: index % max(gifs.count, 1)] {
                placements.append(
                    EnhancementPlacement(
                        kind: "gif",
                        assetId: gif.id,
                        startTime: caption.startTime,
                        endTime: caption.startTime + (gif.defaultDuration ?? 1.2),
                        x: 0.82,
                        y: 0.24,
                        scale: gif.defaultScale ?? 1,
                        rotation: 0,
                        reason: "Local GIF"
                    )
                )
            }
            if index.isMultiple(of: 3), let png = pngs[safe: index % max(pngs.count, 1)] {
                placements.append(
                    EnhancementPlacement(
                        kind: "png",
                        assetId: png.id,
                        startTime: caption.startTime + 0.1,
                        endTime: caption.startTime + (png.defaultDuration ?? 2),
                        x: 0.18,
                        y: 0.3,
                        scale: png.defaultScale ?? 1,
                        rotation: -6,
                        reason: "Local PNG"
                    )
                )
            }
            if let sound = sfx[safe: index % max(sfx.count, 1)] {
                placements.append(
                    EnhancementPlacement(
                        kind: "sfx",
                        assetId: sound.id,
                        startTime: caption.startTime,
                        endTime: caption.startTime + 0.4,
                        x: 0.5,
                        y: 0.5,
                        scale: 1,
                        rotation: 0,
                        reason: "Local SFX"
                    )
                )
            }
        }

        return EnhancementPlan(
            summary: "On-device heuristic placements from bundled libraries.",
            placements: placements,
            source: "swift-local-fallback",
            model: nil,
            note: "Enhancer unreachable — applied local library heuristics"
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
