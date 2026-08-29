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
        safeZone: SafeZone? = nil,
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
        if let safeZone {
            body["safeZone"] = [
                "xMin": safeZone.xMin,
                "xMax": safeZone.xMax,
                "yMin": safeZone.yMin,
                "yMax": safeZone.yMax
            ]
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

    /// Offline path used when the Node enhancer isn't running — mirrors
    /// `AssetLibraries/heuristic/parity-contract.json` + server `heuristicPlan`.
    func localHeuristicPlan(
        captions: [CaptionSegment],
        duration: TimeInterval,
        libraries: MediaLibraryStore,
        language: AppLanguage = .english,
        pack: ShortsPack? = nil,
        safeZone: SafeZone? = nil
    ) -> EnhancementPlan {
        let rules = HeuristicParity.rules
        let stride = rules.captionStride ?? 2
        let maxPerCap = rules.maxWordsPerFilledCaption ?? 1
        let textMod = rules.textPlacementCaptionModulo ?? 3
        let textPrefix = rules.textPrefixWords ?? 3
        let textX = CGFloat(rules.textX ?? 0.5)
        let textY = CGFloat(rules.textY ?? 0.28)
        let textRot = CGFloat(rules.textRotation ?? 0)
        let xBase = CGFloat(rules.wordHitXBase ?? 0.42)
        let xStep = CGFloat(rules.wordHitXStep ?? 0.16)
        let yBase = CGFloat(rules.wordHitYBase ?? 0.34)
        let yStep = CGFloat(rules.wordHitYStep ?? 0.05)
        let hitScale = CGFloat(rules.wordHitScale ?? 1.2)
        let openMin = rules.openingSfxMinDuration ?? 1.5
        let preferredOpen = rules.openingSfxPreferredIds ?? ["riser", "bass-hit"]
        let sourceTag = rules.sourceTag ?? "heuristic-fallback"
        let offlineNote = rules.swiftOfflineNote
            ?? "Enhancer unreachable — local plan mirrors parity-contract v\(HeuristicParity.version)"

        var placements: [EnhancementPlacement] = []
        var wordHits: [EnhancementPlacement] = []
        let texts = libraries.items(for: .textStyles)
        let gifs = libraries.items(for: .gifs)
        let pngs = libraries.items(for: .pngs)
        let sfx = libraries.items(for: .sfx)
        let fonts = Self.scriptFonts(libraries.items(for: .fonts), language: language)
        let effects = libraries.items(for: .effects)
        let effectPoolBase: [MediaLibraryItem] = {
            guard let pack else { return effects }
            let biased = pack.effectBias.compactMap { id in effects.first { $0.id == id } }
            return biased.isEmpty ? effects : biased
        }()
        let punchyIds = HeuristicParity.punchyEffectIds
        let punchy = effectPoolBase.filter { punchyIds.contains($0.id) }
        let effectPool = punchy.isEmpty ? effectPoolBase : punchy
        let sfxPool: [MediaLibraryItem] = {
            guard let pack else { return sfx }
            let biased = pack.sfxBias.compactMap { id in sfx.first { $0.id == id } }
            return biased.isEmpty ? sfx : biased
        }()
        let hitsPer = min(2, max(1, pack?.wordHitsPerCaption ?? 1))
        let hookWindow = pack?.requireHookInFirstSeconds ?? 3

        // Sparse word hits — even captions only, one strong word (parity contract).
        for (index, caption) in captions.enumerated() {
            guard index % stride == 0 else { continue }
            let sig = Self.significantWords(in: caption, limit: max(hitsPer, maxPerCap), language: language)
            guard let word = sig.prefix(maxPerCap).first,
                  let font = fonts[safe: index % max(fonts.count, 1)],
                  let effect = effectPool[safe: (index * 3) % max(effectPool.count, 1)]
            else { continue }
            let preferred = (effect.preferredSfx ?? []).compactMap { id in
                sfxPool.first { $0.id == id } ?? sfx.first { $0.id == id }
            }
            let sound = preferred.first
                ?? sfxPool[safe: index % max(sfxPool.count, 1)]
                ?? sfx.first
            let colors = effect.colors ?? HeuristicParity.wordHitColors
            let primary = Self.punchColor(colors.first)
            let secondary = Self.punchColor(colors.count > 1 ? colors[1] : "#FF2D2D", fallback: "#FF2D2D")
            wordHits.append(
                EnhancementPlacement(
                    kind: "wordHit",
                    assetId: font.id,
                    startTime: word.startTime,
                    endTime: word.endTime,
                    x: xBase + CGFloat(index % 2) * xStep,
                    y: yBase + CGFloat(index % 3) * yStep,
                    scale: hitScale,
                    rotation: index.isMultiple(of: 2) ? -4 : 4,
                    text: word.text,
                    reason: "Sparse fill \"\(word.text)\" → \(effect.id)",
                    lengthSeconds: effect.playLength,
                    captionIndex: index,
                    wordIndex: word.index,
                    fontId: font.id,
                    effectId: effect.id,
                    sfxId: sound?.id,
                    color: primary,
                    secondaryColor: secondary,
                    word: word.text
                )
            )
        }

        // Support text on every Nth caption (parity: modulo 3, prefix 3, rotation 0).
        for (index, caption) in captions.enumerated() {
            guard index % textMod == 0, let text = texts[safe: index % max(texts.count, 1)] else { continue }
            let raw = EnhancementPlacement(
                kind: "text",
                assetId: text.id,
                startTime: caption.startTime,
                endTime: caption.startTime + text.playLength,
                x: textX,
                y: textY,
                scale: 1,
                rotation: textRot,
                text: caption.text.split(separator: " ").prefix(textPrefix).joined(separator: " "),
                reason: "Support text on caption \(index)",
                lengthSeconds: text.playLength,
                captionIndex: index
            )
            let aligned = PlacementAligner.align(
                raw, asset: text, kind: "text", captions: captions, videoDuration: duration, safeZone: safeZone
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

        // Opening / cold-open SFX
        if duration > openMin {
            var riser: MediaLibraryItem?
            for id in preferredOpen {
                riser = sfxPool.first { $0.id == id } ?? sfx.first { $0.id == id }
                if riser != nil { break }
            }
            riser = riser ?? sfx.first
            if let riser {
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
                        reason: "Cold-open \(riser.id) exact \(riser.playLength)s",
                        lengthSeconds: riser.playLength,
                        captionIndex: 0
                    ),
                    at: 0
                )
            }
        }

        // Opening hook: prefer early spoken word, else synthetic WAIT (mirrors ensureOpeningHook).
        if !wordHits.contains(where: { $0.startTime < hookWindow }) {
            let earlyWords: [SigWord] = captions.flatMap { cap in
                Self.significantWords(in: cap, limit: 8, language: language)
                    .filter { $0.startTime < hookWindow }
            }
            let wait: String
            switch language {
            case .hindi: wait = "रुको"
            case .telugu: wait = "ఆగు"
            case .english: wait = "WAIT"
            }
            if let font = fonts.first, let effect = effectPool.first {
                let colors = effect.colors ?? HeuristicParity.wordHitColors
                let sound = sfxPool.first(where: { $0.id == "riser" }) ?? sfxPool.first ?? sfx.first
                if let early = earlyWords.max(by: { $0.text.count < $1.text.count }) {
                    wordHits.insert(
                        EnhancementPlacement(
                            kind: "wordHit",
                            assetId: font.id,
                            startTime: early.startTime,
                            endTime: early.endTime,
                            x: 0.5,
                            y: 0.38,
                            scale: 1.45,
                            rotation: -4,
                            text: early.text,
                            reason: "Opening retention hook",
                            lengthSeconds: effect.playLength,
                            captionIndex: 0,
                            wordIndex: early.index,
                            fontId: font.id,
                            effectId: effect.id,
                            sfxId: sound?.id,
                            color: Self.punchColor(colors.first),
                            secondaryColor: Self.punchColor(colors.count > 1 ? colors[1] : "#FF2D2D", fallback: "#FF2D2D"),
                            word: early.text
                        ),
                        at: 0
                    )
                } else {
                    wordHits.insert(
                        EnhancementPlacement(
                            kind: "wordHit",
                            assetId: font.id,
                            startTime: 0.2,
                            endTime: min(duration, 1.2),
                            x: 0.5,
                            y: 0.36,
                            scale: 1.35,
                            rotation: -5,
                            text: wait,
                            reason: "Synthetic WAIT hook",
                            lengthSeconds: effect.playLength,
                            captionIndex: 0,
                            fontId: font.id,
                            effectId: effect.id,
                            sfxId: sound?.id,
                            color: Self.punchColor(colors.first),
                            secondaryColor: Self.punchColor(colors.count > 1 ? colors[1] : "#FF2D2D", fallback: "#FF2D2D"),
                            word: wait
                        ),
                        at: 0
                    )
                }
            }
        }

        // Density cap + sparse SFX (mirrors validatePlacements thinning).
        wordHits = HeuristicParity.thinWordHits(
            wordHits,
            maxPer15: HeuristicParity.maxWordHitsPer15s(pack: pack)
        )
        let sfxEvery = HeuristicParity.wordHitSfxEveryN(pack: pack)
        wordHits = wordHits.enumerated().map { i, hit in
            var copy = hit
            if i % sfxEvery != 0 { copy.sfxId = nil }
            // Hold through caption like alignWordHit (bounded).
            if let ci = hit.captionIndex, captions.indices.contains(ci) {
                let cap = captions[ci]
                let effectLen = libraries.item(kind: .effects, id: hit.effectId ?? "")?.playLength ?? 1.0
                let holdEnd = min(duration, hit.startTime + max(hit.endTime - hit.startTime, min(effectLen, 1.4)))
                copy.endTime = min(holdEnd, cap.endTime + 0.15)
            }
            return copy
        }

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

        placements = placements.map { placement in
            guard placement.kind == "gif" || placement.kind == "png",
                  let asset = libraries.item(
                    kind: placement.kind == "gif" ? .gifs : .pngs,
                    id: placement.assetId
                  )
            else { return placement }
            let end = min(duration, placement.startTime + asset.playLength)
            var x = placement.x
            var y = placement.y
            if let safeZone {
                let clamped = safeZone.clamp(x: x, y: y)
                x = clamped.0
                y = clamped.1
            }
            return EnhancementPlacement(
                kind: placement.kind,
                assetId: placement.assetId,
                startTime: placement.startTime,
                endTime: end,
                x: x,
                y: y,
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

        // Thin standalone SFX (keep cold-open).
        var standaloneIdx: [Int] = []
        for (i, p) in placements.enumerated() where p.kind == "sfx" {
            standaloneIdx.append(i)
        }
        var drop = Set<Int>()
        for (n, i) in standaloneIdx.enumerated() {
            if placements[i].startTime < 0.35 { continue }
            if n % 2 == 1 { drop.insert(i) }
        }
        if !drop.isEmpty {
            placements = placements.enumerated().compactMap { drop.contains($0.offset) ? nil : $0.element }
        }

        if let safeZone {
            let yMaxHit = min(safeZone.yMax, 0.58)
            let yMinHit = max(safeZone.yMin, 0.14)
            let hitZone = SafeZone(xMin: safeZone.xMin, xMax: safeZone.xMax, yMin: yMinHit, yMax: yMaxHit)
            wordHits = wordHits.map { hit in
                var copy = hit
                let approxChars = max(1, CGFloat(hit.displayText.count))
                let scale = min(1.45, max(0.9, hit.scale == 0 ? 1.2 : hit.scale))
                let halfW = min(0.28, 0.06 * scale * approxChars)
                let halfH = min(0.1, 0.055 * scale)
                var x = min(safeZone.xMax - halfW, max(safeZone.xMin + halfW, hit.x))
                var y = min(yMaxHit - halfH, max(yMinHit + halfH, hit.y))
                (x, y) = hitZone.clamp(x: x, y: y)
                copy.x = x
                copy.y = y
                copy.scale = scale
                return copy
            }
        }

        return EnhancementPlan(
            summary: pack.map { "Heuristic pack \"\($0.name)\": word hits + B-roll stickers snapped to timings." }
                ?? "Heuristic: significant words with fonts/effects/SFX + auto B-roll stickers.",
            placements: placements,
            wordHits: wordHits,
            packId: pack?.id,
            distribution: DistributionPackage.heuristic(
                captions: captions,
                language: language,
                packName: pack?.name
            ),
            safeZone: safeZone,
            source: sourceTag,
            model: nil,
            note: offlineNote + " (parity v\(HeuristicParity.version))",
            language: language.localeIdentifier,
            heuristicParityVersion: HeuristicParity.version
        )
    }

    private static func punchColor(_ hex: String?, fallback: String = "#FFEF5A") -> String {
        guard let hex, hex.hasPrefix("#") else { return fallback }
        let u = hex.uppercased()
        if u == "#FFFFFF" || u == "#FFF" || u == "#FFFFFFFF" { return fallback }
        return hex
    }

    private static func scriptFonts(_ fonts: [MediaLibraryItem], language: AppLanguage) -> [MediaLibraryItem] {
        let filtered = fonts.filter { item in
            let scripts = item.scripts ?? []
            // TE/HI videos are code-switched — allow primary script fonts + Latin for English inserts.
            return scripts.contains(where: { language.scriptTags.contains($0) })
        }
        return filtered.isEmpty ? fonts : filtered
    }

    /// Pick Kohinoor Telugu/Devanagari for native words; Latin fonts for English inserts.
    private static func fontMatchingScript(
        _ text: String,
        in fonts: [MediaLibraryItem],
        fallbackIndex: Int
    ) -> MediaLibraryItem? {
        let wantsTelugu = text.unicodeScalars.contains { (0x0C00...0x0C7F).contains($0.value) }
        let wantsHindi = text.unicodeScalars.contains { (0x0900...0x097F).contains($0.value) }
        let pool: [MediaLibraryItem]
        if wantsTelugu {
            pool = fonts.filter { ($0.scripts ?? []).contains(where: { ["te", "telugu"].contains($0) }) }
        } else if wantsHindi {
            pool = fonts.filter { ($0.scripts ?? []).contains(where: { ["hi", "hindi", "devanagari"].contains($0) }) }
        } else {
            pool = fonts.filter { ($0.scripts ?? []).contains(where: { ["en", "latin"].contains($0) }) }
        }
        let use = pool.isEmpty ? fonts : pool
        return use[safe: fallbackIndex % max(use.count, 1)] ?? use.first
    }

    private struct SigWord {
        var text: String
        var index: Int
        var startTime: TimeInterval
        var endTime: TimeInterval
    }

    private static func significantWords(in caption: CaptionSegment, limit: Int, language: AppLanguage) -> [SigWord] {
        let filler = HeuristicParity.fillerWords
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
        let minLen = language == .english
            ? (HeuristicParity.rules.minTokenLengthEn ?? 3)
            : (HeuristicParity.rules.minTokenLengthOther ?? 2)
        return parts
            .filter { !$0.text.isEmpty && !filler.contains($0.text.lowercased()) && $0.text.count >= minLen }
            .sorted {
                hitScore($0.text, language: language) > hitScore($1.text, language: language)
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Prefer native-script words for TE/HI so English inserts don't monopolize hits.
    private static func hitScore(_ text: String, language: AppLanguage) -> Int {
        var score = StrongWordLexicon.score(text, language: language)
        // Also score English inserts against the English lexicon when code-switching.
        if language != .english {
            score = max(score, StrongWordLexicon.score(text, language: .english))
        }
        if language == .telugu, text.unicodeScalars.contains(where: { (0x0C00...0x0C7F).contains($0.value) }) {
            score += 28
        }
        if language == .hindi, text.unicodeScalars.contains(where: { (0x0900...0x097F).contains($0.value) }) {
            score += 28
        }
        return score
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
