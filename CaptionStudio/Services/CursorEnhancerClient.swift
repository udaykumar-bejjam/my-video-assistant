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
        videoSize: CGSize? = nil,
        language: AppLanguage = .english,
        forceHeuristic: Bool = false
    ) async throws -> EnhancementPlan {
        let url = baseURL.appendingPathComponent("enhance")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        var body: [String: Any] = [
            "duration": duration,
            "forceHeuristic": forceHeuristic,
            "language": language.localeIdentifier,
            "captions": captions.map { cap -> [String: Any] in
                var dict: [String: Any] = [
                    "text": cap.text,
                    "startTime": cap.startTime,
                    "endTime": cap.endTime
                ]
                if !cap.words.isEmpty {
                    dict["words"] = cap.words.map { [
                        "text": $0.text,
                        "startTime": $0.startTime,
                        "endTime": $0.endTime
                    ] as [String: Any] }
                }
                return dict
            }
        ]
        if let videoSize {
            body["videoSize"] = [
                "width": videoSize.width,
                "height": videoSize.height
            ]
        }
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

    /// Offline path used when the Node enhancer isn't running — still uses measured library lengths.
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
                let raw = EnhancementPlacement(
                    kind: "text",
                    assetId: text.id,
                    startTime: caption.startTime,
                    endTime: caption.startTime + text.playLength,
                    x: 0.5,
                    y: 0.28,
                    scale: 1,
                    rotation: index.isMultiple(of: 2) ? -2 : 3,
                    text: caption.text.split(separator: " ").prefix(4).joined(separator: " "),
                    reason: "Text hold \(text.playLength)s on caption \(index)",
                    lengthSeconds: text.playLength,
                    captionIndex: index
                )
                let aligned = PlacementAligner.align(
                    raw, asset: text, kind: "text", captions: captions, videoDuration: duration
                )
                placements.append(
                    EnhancementPlacement(
                        kind: raw.kind,
                        assetId: raw.assetId,
                        startTime: aligned.start,
                        endTime: aligned.end,
                        x: aligned.x,
                        y: aligned.y,
                        scale: raw.scale,
                        rotation: raw.rotation,
                        text: raw.text,
                        reason: raw.reason,
                        lengthSeconds: text.playLength,
                        captionIndex: index,
                        assetPixelSize: .init(width: text.pixelSize.width, height: text.pixelSize.height)
                    )
                )
            }
            if index.isMultiple(of: 2), let gif = gifs[safe: index % max(gifs.count, 1)] {
                let raw = EnhancementPlacement(
                    kind: "gif",
                    assetId: gif.id,
                    startTime: caption.startTime,
                    endTime: caption.startTime + gif.playLength,
                    x: 0.82,
                    y: 0.24,
                    scale: gif.defaultScale ?? 1,
                    rotation: 0,
                    reason: "GIF cycle \(gif.playLength)s",
                    lengthSeconds: gif.playLength,
                    captionIndex: index
                )
                let aligned = PlacementAligner.align(
                    raw, asset: gif, kind: "gif", captions: captions, videoDuration: duration
                )
                placements.append(
                    EnhancementPlacement(
                        kind: "gif",
                        assetId: gif.id,
                        startTime: aligned.start,
                        endTime: aligned.end,
                        x: aligned.x,
                        y: aligned.y,
                        scale: raw.scale,
                        rotation: 0,
                        reason: raw.reason,
                        lengthSeconds: gif.playLength,
                        captionIndex: index,
                        assetPixelSize: .init(width: gif.pixelSize.width, height: gif.pixelSize.height)
                    )
                )
            }
            if index.isMultiple(of: 3), let png = pngs[safe: index % max(pngs.count, 1)] {
                let raw = EnhancementPlacement(
                    kind: "png",
                    assetId: png.id,
                    startTime: caption.startTime,
                    endTime: caption.startTime + png.playLength,
                    x: 0.18,
                    y: 0.3,
                    scale: png.defaultScale ?? 1,
                    rotation: -6,
                    reason: "PNG \(Int(png.pixelSize.width))x\(Int(png.pixelSize.height))",
                    lengthSeconds: png.playLength,
                    captionIndex: index
                )
                let aligned = PlacementAligner.align(
                    raw, asset: png, kind: "png", captions: captions, videoDuration: duration
                )
                placements.append(
                    EnhancementPlacement(
                        kind: "png",
                        assetId: png.id,
                        startTime: aligned.start,
                        endTime: aligned.end,
                        x: aligned.x,
                        y: aligned.y,
                        scale: raw.scale,
                        rotation: raw.rotation,
                        reason: raw.reason,
                        lengthSeconds: png.playLength,
                        captionIndex: index,
                        assetPixelSize: .init(width: png.pixelSize.width, height: png.pixelSize.height)
                    )
                )
            }
            if let sound = sfx[safe: index % max(sfx.count, 1)] {
                placements.append(
                    EnhancementPlacement(
                        kind: "sfx",
                        assetId: sound.id,
                        startTime: caption.startTime,
                        endTime: caption.startTime + sound.playLength,
                        x: 0.5,
                        y: 0.5,
                        scale: 1,
                        rotation: 0,
                        reason: "SFX exact \(sound.playLength)s",
                        lengthSeconds: sound.playLength,
                        captionIndex: index
                    )
                )
            }
        }

        return EnhancementPlan(
            summary: "On-device placements snapped to measured asset lengths and caption windows.",
            placements: placements,
            source: "swift-local-fallback",
            model: nil,
            note: "Enhancer unreachable — local aligner used library duration/size metadata"
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
