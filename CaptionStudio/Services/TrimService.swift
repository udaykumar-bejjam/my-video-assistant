import Foundation

/// Suggests non-destructive silence / filler trims from word-level caption timings.
enum TrimService {
    static let defaultSilenceThreshold: TimeInterval = 0.45

    static let englishFillers: Set<String> = [
        "um", "uh", "uhm", "erm", "ah", "eh", "like", "youknow", "youknowwhat"
    ]

    static let hindiFillers: Set<String> = [
        "अं", "उम्", "आह", "मतलब", "वो", "ना"
    ]

    static let teluguFillers: Set<String> = [
        "ఆ", "ఉం", "అంటే", "కదా"
    ]

    static func fillers(for language: AppLanguage) -> Set<String> {
        switch language {
        case .english: return englishFillers
        case .hindi: return hindiFillers.union(englishFillers)
        case .telugu: return teluguFillers.union(englishFillers)
        }
    }

    static func suggestions(
        captions: [CaptionSegment],
        duration: TimeInterval,
        language: AppLanguage,
        silenceThreshold: TimeInterval = defaultSilenceThreshold
    ) -> [TrimSuggestion] {
        let words = flattenWords(captions: captions, duration: duration)
        guard !words.isEmpty else { return [] }

        var result: [TrimSuggestion] = []
        let fillerSet = fillers(for: language)

        // Leading silence
        if let first = words.first, first.startTime > silenceThreshold {
            result.append(
                TrimSuggestion(
                    startTime: 0,
                    endTime: first.startTime,
                    reason: "silence"
                )
            )
        }

        // Gaps between words
        for index in 0..<(words.count - 1) {
            let current = words[index]
            let next = words[index + 1]
            let gap = next.startTime - current.endTime
            if gap > silenceThreshold {
                result.append(
                    TrimSuggestion(
                        startTime: current.endTime,
                        endTime: next.startTime,
                        reason: "silence"
                    )
                )
            }
        }

        // Trailing silence
        if let last = words.last, duration - last.endTime > silenceThreshold {
            result.append(
                TrimSuggestion(
                    startTime: last.endTime,
                    endTime: duration,
                    reason: "silence"
                )
            )
        }

        // Filler words — trim the word span itself
        for word in words {
            let normalized = normalize(word.text)
            if fillerSet.contains(normalized) {
                result.append(
                    TrimSuggestion(
                        startTime: word.startTime,
                        endTime: max(word.endTime, word.startTime + 0.05),
                        reason: "filler"
                    )
                )
            }
        }

        return mergeOverlapping(result).sorted { $0.startTime < $1.startTime }
    }

    /// Keep ranges after removing accepted cut suggestions from a timeline.
    static func keepRanges(
        duration: TimeInterval,
        removing cuts: [TrimSuggestion]
    ) -> [(start: TimeInterval, end: TimeInterval)] {
        let merged = mergeOverlapping(cuts).sorted { $0.startTime < $1.startTime }
        var keeps: [(TimeInterval, TimeInterval)] = []
        var cursor: TimeInterval = 0
        for cut in merged {
            let start = max(0, min(duration, cut.startTime))
            let end = max(start, min(duration, cut.endTime))
            if start > cursor + 0.001 {
                keeps.append((cursor, start))
            }
            cursor = max(cursor, end)
        }
        if cursor < duration - 0.001 {
            keeps.append((cursor, duration))
        }
        return keeps.filter { $0.1 - $0.0 > 0.01 }
    }

    /// Map an absolute time into the post-trim timeline.
    static func mapTime(
        _ time: TimeInterval,
        through keeps: [(start: TimeInterval, end: TimeInterval)]
    ) -> TimeInterval? {
        var offset: TimeInterval = 0
        for keep in keeps {
            if time < keep.start {
                return nil // inside a removed region
            }
            if time <= keep.end {
                return offset + (time - keep.start)
            }
            offset += keep.end - keep.start
        }
        return nil
    }

    static func shiftCaptions(
        _ captions: [CaptionSegment],
        through keeps: [(start: TimeInterval, end: TimeInterval)]
    ) -> [CaptionSegment] {
        captions.compactMap { caption in
            guard
                let start = mapTime(caption.startTime, through: keeps),
                let end = mapTime(min(caption.endTime, keeps.last?.end ?? caption.endTime), through: keeps)
                    ?? mapClampedEnd(caption.endTime, through: keeps)
            else { return nil }
            var words: [CaptionWord] = []
            for word in caption.words {
                guard
                    let ws = mapTime(word.startTime, through: keeps),
                    let we = mapTime(word.endTime, through: keeps) ?? mapClampedEnd(word.endTime, through: keeps)
                else { continue }
                words.append(CaptionWord(id: word.id, text: word.text, startTime: ws, endTime: max(ws + 0.01, we)))
            }
            var next = caption
            next.startTime = start
            next.endTime = max(start + 0.05, end)
            next.words = words
            // Drop captions whose words were entirely fillers and span collapsed
            if next.endTime <= next.startTime { return nil }
            return next
        }
    }

    static func shiftOverlays(
        _ overlays: [OverlayItem],
        through keeps: [(start: TimeInterval, end: TimeInterval)]
    ) -> [OverlayItem] {
        overlays.compactMap { item in
            guard
                let start = mapTime(item.startTime, through: keeps),
                let end = mapTime(item.endTime, through: keeps) ?? mapClampedEnd(item.endTime, through: keeps)
            else { return nil }
            var next = item
            next.startTime = start
            next.endTime = max(start + 0.05, end)
            return next
        }
    }

    static func shiftSFX(
        _ cues: [SoundEffectCue],
        through keeps: [(start: TimeInterval, end: TimeInterval)]
    ) -> [SoundEffectCue] {
        cues.compactMap { cue in
            guard let start = mapTime(cue.startTime, through: keeps) else { return nil }
            var next = cue
            next.startTime = start
            return next
        }
    }

    static func trimmedDuration(keeps: [(start: TimeInterval, end: TimeInterval)]) -> TimeInterval {
        keeps.reduce(0) { $0 + ($1.end - $1.start) }
    }

    // MARK: - Helpers

    private struct TimedWord {
        var text: String
        var startTime: TimeInterval
        var endTime: TimeInterval
    }

    private static func flattenWords(captions: [CaptionSegment], duration: TimeInterval) -> [TimedWord] {
        var words: [TimedWord] = []
        for caption in captions.sorted(by: { $0.startTime < $1.startTime }) {
            if !caption.words.isEmpty {
                words.append(contentsOf: caption.words.map {
                    TimedWord(text: $0.text, startTime: $0.startTime, endTime: $0.endTime)
                })
            } else {
                let tokens = caption.text.split(separator: " ").map(String.init).filter { !$0.isEmpty }
                guard !tokens.isEmpty else { continue }
                let span = caption.duration / Double(tokens.count)
                for (i, token) in tokens.enumerated() {
                    words.append(
                        TimedWord(
                            text: token,
                            startTime: caption.startTime + Double(i) * span,
                            endTime: caption.startTime + Double(i + 1) * span
                        )
                    )
                }
            }
        }
        return words
            .map {
                TimedWord(
                    text: $0.text,
                    startTime: max(0, min(duration, $0.startTime)),
                    endTime: max(0, min(duration, $0.endTime))
                )
            }
            .sorted { $0.startTime < $1.startTime }
    }

    private static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private static func mergeOverlapping(_ items: [TrimSuggestion]) -> [TrimSuggestion] {
        guard !items.isEmpty else { return [] }
        let sorted = items.sorted { $0.startTime < $1.startTime }
        var merged: [TrimSuggestion] = []
        var current = sorted[0]
        for next in sorted.dropFirst() {
            if next.startTime <= current.endTime + 0.02 {
                current.endTime = max(current.endTime, next.endTime)
                if current.reason != next.reason {
                    current.reason = "silence+filler"
                }
            } else {
                merged.append(current)
                current = next
            }
        }
        merged.append(current)
        return merged
    }

    private static func mapClampedEnd(
        _ time: TimeInterval,
        through keeps: [(start: TimeInterval, end: TimeInterval)]
    ) -> TimeInterval? {
        // If end falls inside a cut, clamp to end of previous keep.
        var offset: TimeInterval = 0
        var lastKeepEndMapped: TimeInterval?
        for keep in keeps {
            if time >= keep.start && time <= keep.end {
                return offset + (time - keep.start)
            }
            if time > keep.end {
                offset += keep.end - keep.start
                lastKeepEndMapped = offset
            } else if time < keep.start {
                return lastKeepEndMapped
            }
        }
        return lastKeepEndMapped
    }
}
