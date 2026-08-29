import Foundation
import CoreGraphics

/// Loads `AssetLibraries/heuristic/parity-contract.json` so the offline Swift
/// enhance path mirrors enhancer-server `heuristicCore.js` (P0.1).
enum HeuristicParity {
    struct Rules: Decodable {
        var captionStride: Int?
        var maxWordsPerFilledCaption: Int?
        var minTokenLengthEn: Int?
        var minTokenLengthOther: Int?
        var textPlacementCaptionModulo: Int?
        var textPrefixWords: Int?
        var textX: Double?
        var textY: Double?
        var textRotation: Double?
        var wordHitXBase: Double?
        var wordHitXStep: Double?
        var wordHitYBase: Double?
        var wordHitYStep: Double?
        var wordHitScale: Double?
        var openingSfxMinDuration: Double?
        var openingSfxPreferredIds: [String]?
        var sourceTag: String?
        var swiftOfflineNote: String?
    }

    struct Contract: Decodable {
        var version: String
        var fillerWords: [String]
        var punchyEffectIds: [String]
        var wordHitColors: [String]
        var rules: Rules
    }

    private static var cached: Contract?

    static var version: String { contract.version }

    static var contract: Contract {
        if let cached { return cached }
        let loaded = load() ?? fallbackContract
        cached = loaded
        return loaded
    }

    static var fillerWords: Set<String> {
        Set(contract.fillerWords.map { $0.lowercased() })
    }

    static var punchyEffectIds: [String] { contract.punchyEffectIds }
    static var wordHitColors: [String] { contract.wordHitColors }
    static var rules: Rules { contract.rules }

    /// Same rolling-window density cap as Node `thinWordHits`.
    static func thinWordHits(_ hits: [EnhancementPlacement], maxPer15: Int) -> [EnhancementPlacement] {
        guard !hits.isEmpty else { return [] }
        let sorted = hits.sorted { $0.startTime < $1.startTime }
        var kept: [EnhancementPlacement] = []
        for hit in sorted {
            let inWindow = kept.filter { abs($0.startTime - hit.startTime) <= 15 }.count
            if inWindow < maxPer15 {
                kept.append(hit)
            }
        }
        return kept
    }

    static func maxWordHitsPer15s(pack: ShortsPack?) -> Int {
        switch pack?.gifDensity ?? "medium" {
        case "high": return 3
        case "low": return 1
        default: return 2
        }
    }

    static func wordHitSfxEveryN(pack: ShortsPack?) -> Int {
        switch pack?.gifDensity ?? "medium" {
        case "high": return 2
        case "low": return 4
        default: return 3
        }
    }

    private static func load() -> Contract? {
        let candidates: [URL] = {
            var urls: [URL] = []
            if let bundled = Bundle.main.url(
                forResource: "parity-contract",
                withExtension: "json",
                subdirectory: "Libraries/heuristic"
            ) ?? Bundle.main.url(forResource: "parity-contract", withExtension: "json") {
                urls.append(bundled)
            }
            var dir = URL(fileURLWithPath: #file).deletingLastPathComponent()
            for _ in 0..<6 {
                let roots = [
                    dir.appendingPathComponent("AssetLibraries"),
                    dir.appendingPathComponent("../AssetLibraries"),
                    dir.appendingPathComponent("../../AssetLibraries")
                ]
                for root in roots {
                    let resolved = root.standardizedFileURL
                    let file = resolved.appendingPathComponent("heuristic/parity-contract.json")
                    if FileManager.default.fileExists(atPath: file.path) {
                        urls.append(file)
                    }
                }
                dir = dir.deletingLastPathComponent()
            }
            return urls
        }()

        for url in candidates {
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode(Contract.self, from: data) {
                return decoded
            }
        }
        return nil
    }

    /// Hardcoded mirror of `AssetLibraries/heuristic/parity-contract.json` when the file isn't bundled yet.
    private static var fallbackContract: Contract {
        Contract(
            version: "1",
            fillerWords: [
                "a", "an", "the", "to", "of", "and", "or", "in", "on", "is", "are", "for", "with", "this", "that",
                "एक", "और", "की", "के", "को", "में", "से", "है", "हैं", "का", "कि",
                "ఒక", "మరియు", "లో", "కి", "నుంచి", "ఉంది", "అని"
            ],
            punchyEffectIds: [
                "punch", "color-pulse", "fire-pulse", "stomp", "slam", "shake", "neon-pulse", "pulse", "glitch"
            ],
            wordHitColors: ["#FFEF5A", "#FF2D2D", "#FF9F1C", "#33F2CF", "#FF2D9B"],
            rules: Rules(
                captionStride: 2,
                maxWordsPerFilledCaption: 1,
                minTokenLengthEn: 3,
                minTokenLengthOther: 2,
                textPlacementCaptionModulo: 3,
                textPrefixWords: 3,
                textX: 0.5,
                textY: 0.28,
                textRotation: 0,
                wordHitXBase: 0.42,
                wordHitXStep: 0.16,
                wordHitYBase: 0.34,
                wordHitYStep: 0.05,
                wordHitScale: 1.2,
                openingSfxMinDuration: 1.5,
                openingSfxPreferredIds: ["riser", "bass-hit"],
                sourceTag: "heuristic-fallback",
                swiftOfflineNote: "Enhancer unreachable — local plan mirrors parity-contract v1"
            )
        )
    }
}
