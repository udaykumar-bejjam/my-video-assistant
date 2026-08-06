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
        packId: String? = nil,
        brandKit: BrandKit? = nil,
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
        if let packId {
            body["packId"] = packId
        }
        if let brandKit {
            var kitBody: [String: Any] = [
                "primaryFontId": brandKit.primaryFontId,
                "hindiFontId": brandKit.hindiFontId,
                "teluguFontId": brandKit.teluguFontId,
                "primaryColor": brandKit.primaryColor,
                "secondaryColor": brandKit.secondaryColor,
                "defaultLanguage": brandKit.defaultLanguage,
                "defaultSfxGain": brandKit.defaultSfxGain,
                "preferBrandKit": true
            ]
            if let defaultPackId = brandKit.defaultPackId {
                kitBody["defaultPackId"] = defaultPackId
            }
            body["brandKit"] = kitBody
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

    /// Offline path used when the Node enhancer isn't running — pack-biased word hits + placements.
    func localHeuristicPlan(
        captions: [CaptionSegment],
        duration: TimeInterval,
        libraries: MediaLibraryStore,
        language: AppLanguage = .english,
        pack: ShortsPack? = nil
    ) -> EnhancementPlan {
        var placements: [EnhancementPlacement] = []
        var wordHits: [EnhancementPlacement] = []
        let texts = libraries.items(for: .textStyles)
        let gifs = libraries.items(for: .gifs)
        let pngs = libraries.items(for: .pngs)
        let sfx = libraries.items(for: .sfx)
        let fonts = Self.scriptFonts(libraries.items(for: .fonts), language: language)
        let effects = libraries.items(for: .effects)
        let effectPool: [MediaLibraryItem] = {
            guard let pack else { return effects }
            let biased = pack.effectBias.compactMap { id in effects.first { $0.id == id } }
            return biased.isEmpty ? effects : biased
        }()
        let sfxPool: [MediaLibraryItem] = {
            guard let pack else { return sfx }
            let biased = pack.sfxBias.compactMap { id in sfx.first { $0.id == id } }
            return biased.isEmpty ? sfx : biased
        }()
        let hitsPer = pack?.wordHitsPerCaption ?? 2
        let hookWindow = pack?.requireHookInFirstSeconds ?? 3

        for (index, caption) in captions.prefix(8).enumerated() {
            let sig = Self.significantWords(in: caption, limit: hitsPer, language: language)
            for (wi, word) in sig.enumerated() {
                guard let font = fonts[safe: (index + wi) % max(fonts.count, 1)],
                      let effect = effectPool[safe: (index * 3 + wi * 2) % max(effectPool.count, 1)]
                else { continue }
                let preferred = (effect.preferredSfx ?? []).compactMap { id in sfxPool.first { $0.id == id } ?? sfx.first { $0.id == id } }
                let sound = preferred.first ?? sfxPool[safe: (index + wi) % max(sfxPool.count, 1)] ?? sfx.first
                let colors = effect.colors ?? ["#FFEF5A", "#FF2D2D"]
                let raw = EnhancementPlacement(
                    kind: "wordHit",
                    assetId: font.id,
                    startTime: word.startTime,
                    endTime: word.endTime,
                    x: 0.35 + CGFloat(wi % 2) * 0.3,
                    y: 0.36 + CGFloat(index % 3) * 0.06,
                    scale: 1.35 + CGFloat(wi % 2) * 0.2,
                    rotation: wi.isMultiple(of: 2) ? -5 : 6,
                    text: word.text,
                    reason: "Local pack\(pack.map { ":\($0.id)" } ?? "") hit",
                    lengthSeconds: effect.playLength,
                    captionIndex: index,
                    wordIndex: word.index,
                    fontId: font.id,
                    effectId: effect.id,
                    sfxId: sound?.id,
                    color: colors.first,
                    secondaryColor: colors.count > 1 ? colors[1] : colors.first,
                    word: word.text
                )
                wordHits.append(raw)
            }

            if index.isMultiple(of: 3), let text = texts[safe: index % max(texts.count, 1)] {
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
        }

        // Opening hook SFX
        if duration > 1.5,
           let riser = sfxPool.first(where: { $0.id == "riser" })
            ?? sfxPool.first(where: { $0.id == "bass-hit" })
            ?? sfx.first {
            placements.insert(
                EnhancementPlacement(
                    kind: "sfx",
                    assetId: riser.id,
                    startTime: 0,
                    endTime: riser.playLength,
                    x: 0.5,
                    y: 0.5,
                    scale: 1,
                    rotation: 0,
                    reason: "Opening \(riser.id) \(riser.playLength)s",
                    lengthSeconds: riser.playLength,
                    captionIndex: 0
                ),
                at: 0
            )
        }

        // Guarantee a word hit inside the hook window
        if !wordHits.contains(where: { $0.startTime < hookWindow }),
           let font = fonts.first,
           let effect = effectPool.first {
            let wait: String
            switch language {
            case .hindi: wait = "रुको"
            case .telugu: wait = "ఆగు"
            case .english: wait = "WAIT"
            }
            let colors = effect.colors ?? ["#FFEF5A", "#FF2D2D"]
            let sound = sfxPool.first(where: { $0.id == "riser" }) ?? sfxPool.first ?? sfx.first
            wordHits.insert(
                EnhancementPlacement(
                    kind: "wordHit",
                    assetId: font.id,
                    startTime: 0.2,
                    endTime: min(duration, 1.2),
                    x: 0.5,
                    y: 0.36,
                    scale: 1.5,
                    rotation: -5,
                    text: wait,
                    reason: "Synthetic opening hook",
                    lengthSeconds: effect.playLength,
                    captionIndex: 0,
                    fontId: font.id,
                    effectId: effect.id,
                    sfxId: sound?.id,
                    color: colors.first,
                    secondaryColor: colors.count > 1 ? colors[1] : colors.first,
                    word: wait
                ),
                at: 0
            )
        }

        // A3 — pair strong word hits with GIF/PNG stickers in safe corners
        _ = BrollPlanner.ensureStickers(
            wordHits: wordHits,
            placements: &placements,
            gifs: gifs,
            pngs: pngs,
            sfx: sfx,
            language: language,
            pack: pack,
            duration: duration
        )

        // Align newly added stickers to measured lengths (keep word start — no caption snap)
        placements = placements.map { placement in
            guard placement.kind == "gif" || placement.kind == "png",
                  let asset = libraries.item(
                    kind: placement.kind == "gif" ? .gifs : .pngs,
                    id: placement.assetId
                  )
            else { return placement }
            let end = min(duration, placement.startTime + asset.playLength)
            return EnhancementPlacement(
                kind: placement.kind,
                assetId: placement.assetId,
                startTime: placement.startTime,
                endTime: end,
                x: placement.x,
                y: placement.y,
                scale: placement.scale,
                rotation: placement.rotation,
                text: placement.text,
                reason: placement.reason,
                lengthSeconds: asset.playLength,
                captionIndex: placement.captionIndex,
                wordIndex: placement.wordIndex,
                assetPixelSize: .init(width: asset.pixelSize.width, height: asset.pixelSize.height)
            )
        }

        return EnhancementPlan(
            summary: pack.map { "On-device pack \"\($0.name)\" word hits + B-roll stickers." }
                ?? "On-device placements with auto B-roll stickers on strong words.",
            placements: placements,
            wordHits: wordHits,
            packId: pack?.id,
            source: "swift-local-fallback",
            model: nil,
            note: "Enhancer unreachable — local aligner used library + pack + B-roll biases",
            language: language.localeIdentifier
        )
    }

    private static func scriptFonts(_ fonts: [MediaLibraryItem], language: AppLanguage) -> [MediaLibraryItem] {
        let filtered = fonts.filter { item in
            let scripts = item.scripts ?? []
            switch language {
            case .hindi:
                return scripts.contains(where: { ["hi", "hindi", "devanagari"].contains($0) })
            case .telugu:
                return scripts.contains(where: { ["te", "telugu"].contains($0) })
            case .english:
                return scripts.contains(where: { ["en", "latin"].contains($0) })
            }
        }
        return filtered.isEmpty ? fonts : filtered
    }

    private struct SigWord {
        var text: String
        var index: Int
        var startTime: TimeInterval
        var endTime: TimeInterval
    }

    private static func significantWords(in caption: CaptionSegment, limit: Int, language: AppLanguage) -> [SigWord] {
        let filler: Set<String> = [
            "a", "an", "the", "to", "of", "and", "or", "in", "on", "is", "are", "for", "with", "this", "that",
            "एक", "और", "की", "के", "को", "में", "से", "है", "हैं", "का", "कि",
            "ఒక", "మరియు", "లో", "కి", "నుంచి", "ఉంది", "అని"
        ]
        let parts: [SigWord]
        if !caption.words.isEmpty {
            parts = caption.words.enumerated().map {
                SigWord(text: $0.element.text, index: $0.offset, startTime: $0.element.startTime, endTime: $0.element.endTime)
            }
        } else {
            let tokens = caption.text.split(separator: " ").map(String.init).filter { !$0.isEmpty }
            let span = caption.duration / Double(max(tokens.count, 1))
            parts = tokens.enumerated().map { i, text in
                SigWord(
                    text: text,
                    index: i,
                    startTime: caption.startTime + Double(i) * span,
                    endTime: caption.startTime + Double(i + 1) * span
                )
            }
        }
        return parts
            .filter { !$0.text.isEmpty && !filler.contains($0.text.lowercased()) && $0.text.count > 2 }
            .sorted { StrongWordLexicon.score($0.text, language: language) > StrongWordLexicon.score($1.text, language: language) }
            .prefix(limit)
            .map { $0 }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
