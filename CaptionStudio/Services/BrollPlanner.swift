import Foundation
import CoreGraphics

/// Auto B-roll / sticker moments for strong word hits (A3).
enum BrollPlanner {
    static let safeCorners: [(CGFloat, CGFloat)] = [
        (0.18, 0.20),
        (0.72, 0.20),
        (0.18, 0.58),
        (0.72, 0.55)
    ]

    static func maxStickersPer15s(pack: ShortsPack?) -> Int {
        switch pack?.gifDensity ?? "medium" {
        case "high": return 4
        case "low": return 2
        default: return 3
        }
    }

    /// Append GIF/PNG (+ optional SFX) for strong wordHits that lack a nearby sticker.
    static func ensureStickers(
        wordHits: [EnhancementPlacement],
        placements: inout [EnhancementPlacement],
        gifs: [MediaLibraryItem],
        pngs: [MediaLibraryItem],
        sfx: [MediaLibraryItem],
        language: AppLanguage,
        pack: ShortsPack?,
        duration: TimeInterval
    ) -> Int {
        let maxPer = maxStickersPer15s(pack: pack)
        var added = 0
        var cornerIdx = placements.filter { $0.kind == "gif" || $0.kind == "png" }.count

        let strong: [(hit: EnhancementPlacement, category: StrongWordLexicon.Category, at: TimeInterval, index: Int)] =
            wordHits.enumerated().compactMap { index, hit in
                let word = hit.word ?? hit.text ?? ""
                guard let category = StrongWordLexicon.classify(word, language: language) else { return nil }
                return (hit, category, hit.startTime, index)
            }
            .sorted { $0.at < $1.at }

        for item in strong {
            let at = item.at
            guard at <= duration else { continue }
            if hasNearbySticker(placements, at: at) { continue }
            if stickersInWindow(placements, center: at) >= maxPer { continue }
            guard let picked = pickSticker(gifs: gifs, pngs: pngs, category: item.category, index: item.index)
            else { continue }

            let corner = safeCorners[cornerIdx % safeCorners.count]
            cornerIdx += 1
            let length = picked.asset.playLength
            placements.append(
                EnhancementPlacement(
                    kind: picked.kind,
                    assetId: picked.asset.id,
                    startTime: at,
                    endTime: min(duration, at + length),
                    x: corner.0,
                    y: corner.1,
                    scale: picked.asset.defaultScale ?? 1,
                    rotation: item.index.isMultiple(of: 2) ? -4 : 5,
                    reason: "B-roll sticker for \"\(item.hit.word ?? item.hit.text ?? "")\" (\(item.category.rawValue))",
                    lengthSeconds: length,
                    captionIndex: item.hit.captionIndex,
                    wordIndex: item.hit.wordIndex,
                    assetPixelSize: .init(
                        width: picked.asset.pixelSize.width,
                        height: picked.asset.pixelSize.height
                    )
                )
            )
            added += 1

            let hasSfx = item.hit.sfxId != nil || placements.contains {
                $0.kind == "sfx" && abs($0.startTime - at) <= 0.4
            }
            if !hasSfx, let sound = pickPopSfx(sfx, pack: pack) {
                placements.append(
                    EnhancementPlacement(
                        kind: "sfx",
                        assetId: sound.id,
                        startTime: at,
                        endTime: min(duration, at + sound.playLength),
                        x: 0.5,
                        y: 0.5,
                        scale: 1,
                        rotation: 0,
                        reason: "B-roll SFX for \"\(item.hit.word ?? "")\"",
                        lengthSeconds: sound.playLength,
                        captionIndex: item.hit.captionIndex
                    )
                )
            }
        }
        return added
    }

    private static func hasNearbySticker(_ placements: [EnhancementPlacement], at: TimeInterval, window: TimeInterval = 0.45) -> Bool {
        placements.contains {
            ($0.kind == "gif" || $0.kind == "png") && abs($0.startTime - at) <= window
        }
    }

    private static func stickersInWindow(_ placements: [EnhancementPlacement], center: TimeInterval, half: TimeInterval = 7.5) -> Int {
        placements.filter {
            ($0.kind == "gif" || $0.kind == "png") && $0.startTime >= center - half && $0.startTime <= center + half
        }.count
    }

    private static func pickSticker(
        gifs: [MediaLibraryItem],
        pngs: [MediaLibraryItem],
        category: StrongWordLexicon.Category,
        index: Int
    ) -> (kind: String, asset: MediaLibraryItem)? {
        let tags = StrongWordLexicon.tags(for: category)
        if index.isMultiple(of: 2) {
            if let gif = pickByTags(gifs, tags: tags) { return ("gif", gif) }
            if let png = pickByTags(pngs, tags: tags) { return ("png", png) }
        } else {
            if let png = pickByTags(pngs, tags: tags) { return ("png", png) }
            if let gif = pickByTags(gifs, tags: tags) { return ("gif", gif) }
        }
        return nil
    }

    private static func pickByTags(_ items: [MediaLibraryItem], tags: [String]) -> MediaLibraryItem? {
        guard !items.isEmpty else { return nil }
        if let hit = items.first(where: { item in item.tagList.contains(where: { tags.contains($0) }) }) {
            return hit
        }
        return items.first
    }

    private static func pickPopSfx(_ sfx: [MediaLibraryItem], pack: ShortsPack?) -> MediaLibraryItem? {
        let preferred = (pack?.sfxBias ?? []) + ["pop", "whoosh", "ding", "bass-hit"]
        for id in preferred {
            if let hit = sfx.first(where: { $0.id == id }) { return hit }
        }
        return sfx.first
    }
}

/// EN / Hindi / Telugu strong-word lexicon for B-roll triggers.
enum StrongWordLexicon {
    enum Category: String {
        case power, reveal, emotion, numbers, cta
    }

    private static var cache: [AppLanguage: [String: Category]] = [:]

    static func classify(_ text: String, language: AppLanguage) -> Category? {
        let token = normalize(text)
        guard !token.isEmpty else { return nil }
        if token.range(of: #"^\d+(\.\d+)?%?$"#, options: .regularExpression) != nil {
            return .numbers
        }
        let map = lexicon(for: language)
        if let cat = map[token] { return cat }
        if language == .english {
            if token.hasPrefix("fire") || token.hasPrefix("crazy") || token.hasPrefix("insane") || token.hasPrefix("epic") || token.hasPrefix("hype") {
                return .power
            }
            if token.hasPrefix("secret") || token.hasPrefix("reveal") || token.hasPrefix("watch") || token.hasPrefix("wait") {
                return .reveal
            }
            if token.hasPrefix("love") || token.hasPrefix("heart") || token.hasPrefix("wow") || token.hasPrefix("amaz") {
                return .emotion
            }
            if ["follow", "share", "subscribe", "like", "click", "go"].contains(token) {
                return .cta
            }
        }
        return nil
    }

    static func score(_ text: String, language: AppLanguage) -> Int {
        let token = normalize(text)
        guard token.count >= 2 else { return -1 }
        var score = token.count
        switch classify(token, language: language) {
        case .power, .cta: score += 40
        case .reveal, .emotion: score += 35
        case .numbers: score += 30
        case .none: break
        }
        return score
    }

    static func tags(for category: Category) -> [String] {
        switch category {
        case .power: return ["power", "impact", "hype", "energy", "hot", "celebration"]
        case .reveal: return ["reveal", "focus", "highlight", "new", "premium"]
        case .emotion: return ["love", "emotional", "celebration", "cheer", "like"]
        case .numbers: return ["point", "highlight", "focus", "ui", "label"]
        case .cta: return ["cta", "direction", "point", "product", "premium"]
        }
    }

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’().,!?…:;"))
            .lowercased()
    }

    private static func lexicon(for language: AppLanguage) -> [String: Category] {
        if let cached = cache[language] { return cached }
        let name: String
        switch language {
        case .hindi: name = "hi"
        case .telugu: name = "te"
        case .english: name = "en"
        }
        var map: [String: Category] = [:]
        if let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Libraries/lexicons")
            ?? Bundle.main.url(forResource: name, withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let categories = json["categories"] as? [String: [String]] {
            for (key, words) in categories {
                guard let cat = Category(rawValue: key) else { continue }
                for w in words {
                    map[w.lowercased()] = cat
                }
            }
        } else {
            map = fallback(for: language)
        }
        cache[language] = map
        return map
    }

    private static func fallback(for language: AppLanguage) -> [String: Category] {
        switch language {
        case .hindi:
            return [
                "धमाका": .power, "पावर": .power, "राज़": .reveal, "देखो": .reveal,
                "प्यार": .emotion, "दिल": .emotion, "फॉलो": .cta, "अभी": .cta
            ]
        case .telugu:
            return [
                "గొప్ప": .power, "పవర్": .power, "రహస్యం": .reveal, "చూడండి": .reveal,
                "ప్రేమ": .emotion, "ఫాలో": .cta, "ఇప్పుడు": .cta
            ]
        case .english:
            return [
                "fire": .power, "crazy": .power, "energy": .power, "hype": .power,
                "secret": .reveal, "watch": .reveal, "wait": .reveal,
                "love": .emotion, "wow": .emotion,
                "follow": .cta, "share": .cta, "subscribe": .cta
            ]
        }
    }
}
