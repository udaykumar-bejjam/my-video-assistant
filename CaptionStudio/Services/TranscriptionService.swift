import Foundation
import AVFoundation
import Speech
import Combine

enum TranscriptionError: LocalizedError {
    case noAudioTrack
    case authorizationDenied
    case recognizerUnavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack: return "This video has no audio track to transcribe."
        case .authorizationDenied: return "Speech recognition permission was denied."
        case .recognizerUnavailable: return "Speech recognition is unavailable on this device."
        case .failed(let message): return message
        }
    }
}

/// Timed word with ASR confidence + which locale produced it.
private struct TimedToken: Sendable {
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var confidence: Float
    var localeId: String
}

/// Speech-to-text using Apple's Speech framework.
///
/// Telugu/Hindi creators almost always code-switch with English. A single
/// `te-IN` (or `hi-IN`) recognizer mangles the English inserts (and vice versa),
/// which is why mixed videos looked ~20% right. We dual-pass the primary locale
/// plus `en-US`, then merge by confidence + script.
@MainActor
final class TranscriptionService: ObservableObject {
    @Published var progress: Double = 0
    @Published var statusMessage: String = ""

    var language: AppLanguage = .english

    init(language: AppLanguage = .english) {
        self.language = language
    }

    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Transcribe a local video URL into timed caption segments.
    func transcribe(videoURL: URL, useDemoFallback: Bool = true) async throws -> [CaptionSegment] {
        progress = 0.05
        statusMessage = "Checking permissions…"

        let status = await requestAuthorization()
        guard status == .authorized || status == .notDetermined else {
            if useDemoFallback {
                statusMessage = "Using demo captions (speech permission denied)."
                return demoCaptions(for: videoURL)
            }
            throw TranscriptionError.authorizationDenied
        }

        let localeIds = language.transcriptionLocaleIdentifiers
        let recognizers: [(String, SFSpeechRecognizer)] = localeIds.compactMap { id in
            let locale = Locale(identifier: id)
            guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
                return nil
            }
            return (id, recognizer)
        }

        guard !recognizers.isEmpty else {
            if useDemoFallback {
                statusMessage = "Using demo captions (recognizer unavailable for \(language.localeIdentifier))."
                return demoCaptions(for: videoURL)
            }
            throw TranscriptionError.recognizerUnavailable
        }

        progress = 0.15
        statusMessage = "Extracting audio…"

        let audioURL = try await extractAudio(from: videoURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        do {
            let passes: [[TimedToken]]
            if recognizers.count == 1 {
                progress = 0.35
                statusMessage = "Transcribing (\(recognizers[0].0))…"
                passes = [try await recognizeTokens(audioURL: audioURL, localeId: recognizers[0].0, recognizer: recognizers[0].1)]
            } else {
                progress = 0.3
                statusMessage = "Transcribing mixed \(language.shortLabel) + English…"
                // Sequential passes share one audio file safely; parallel SFSpeech tasks are flaky.
                var collected: [[TimedToken]] = []
                for (index, pair) in recognizers.enumerated() {
                    let (localeId, recognizer) = pair
                    progress = 0.3 + 0.3 * Double(index) / Double(recognizers.count)
                    statusMessage = "Pass \(index + 1)/\(recognizers.count): \(localeId)…"
                    let tokens = try await recognizeTokens(
                        audioURL: audioURL,
                        localeId: localeId,
                        recognizer: recognizer
                    )
                    collected.append(tokens)
                }
                passes = collected
            }

            let merged = Self.mergeCodeSwitchedPasses(passes, primaryLocale: language.localeIdentifier)
            let segments = Self.buildSegments(from: merged, language: language)
            progress = 1

            if segments.isEmpty {
                if useDemoFallback {
                    statusMessage = "No speech detected — showing demo captions."
                    return demoCaptions(for: videoURL)
                }
                return []
            }

            let teCount = merged.filter { Self.script(of: $0.text) == .telugu }.count
            let hiCount = merged.filter { Self.script(of: $0.text) == .devanagari }.count
            let laCount = merged.filter { Self.script(of: $0.text) == .latin }.count
            statusMessage = "Done — \(segments.count) captions (TE:\(teCount) HI:\(hiCount) EN:\(laCount))"
            return segments
        } catch {
            if useDemoFallback {
                statusMessage = "Transcription failed — using demo captions. (\(error.localizedDescription))"
                return demoCaptions(for: videoURL)
            }
            throw TranscriptionError.failed(error.localizedDescription)
        }
    }

    // MARK: - Recognition

    private func recognizeTokens(
        audioURL: URL,
        localeId: String,
        recognizer: SFSpeechRecognizer
    ) async throws -> [TimedToken] {
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if #available(iOS 16, macOS 13, *) {
            request.addsPunctuation = true
        }

        let transcription = try await recognize(request: request, recognizer: recognizer)
        return transcription.segments.map { seg in
            TimedToken(
                text: seg.substring.trimmingCharacters(in: .whitespacesAndNewlines),
                startTime: seg.timestamp,
                endTime: seg.timestamp + max(seg.duration, 0.08),
                confidence: seg.confidence,
                localeId: localeId
            )
        }
        .filter { !$0.text.isEmpty }
    }

    private func recognize(
        request: SFSpeechURLRecognitionRequest,
        recognizer: SFSpeechRecognizer
    ) async throws -> SFTranscription {
        try await withCheckedThrowingContinuation { continuation in
            final class Box { var task: SFSpeechRecognitionTask?; var hasResumed = false }
            let box = Box()
            box.task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                if let result {
                    let fraction = result.isFinal
                        ? 0.95
                        : min(0.9, 0.35 + Double(result.bestTranscription.segments.count) * 0.02)
                    Task { @MainActor in
                        self?.progress = max(self?.progress ?? 0, fraction * 0.5)
                    }
                    if result.isFinal, !box.hasResumed {
                        box.hasResumed = true
                        continuation.resume(returning: result.bestTranscription)
                    }
                } else if let error, !box.hasResumed {
                    box.hasResumed = true
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Code-switch merge

    /// Merge dual-locale token streams. Overlapping words keep the higher-scoring
    /// candidate (confidence × script/locale bonus).
    nonisolated private static func mergeCodeSwitchedPasses(
        _ passes: [[TimedToken]],
        primaryLocale: String
    ) -> [TimedToken] {
        let flat = passes.flatMap { $0 }.filter { !$0.text.isEmpty }
        guard passes.count > 1 else {
            return flat.sorted { $0.startTime < $1.startTime }
        }
        guard !flat.isEmpty else { return [] }

        let sorted = flat.sorted { a, b in
            if abs(a.startTime - b.startTime) > 0.02 { return a.startTime < b.startTime }
            return score(a, primaryLocale: primaryLocale) > score(b, primaryLocale: primaryLocale)
        }

        var chosen: [TimedToken] = []
        for token in sorted {
            if let last = chosen.last, overlaps(last, token) {
                if score(token, primaryLocale: primaryLocale) > score(last, primaryLocale: primaryLocale) {
                    chosen[chosen.count - 1] = token
                }
                continue
            }
            chosen.append(token)
        }
        return chosen
    }

    nonisolated private static func overlaps(_ a: TimedToken, _ b: TimedToken) -> Bool {
        let start = max(a.startTime, b.startTime)
        let end = min(a.endTime, b.endTime)
        let overlap = end - start
        guard overlap > 0 else {
            // Near-simultaneous starts from two locales = same spoken word.
            return abs(a.startTime - b.startTime) < 0.18
        }
        let shorter = min(a.endTime - a.startTime, b.endTime - b.startTime)
        return overlap >= shorter * 0.45
    }

    nonisolated private static func score(_ token: TimedToken, primaryLocale: String) -> Double {
        let conf = Double(max(0.05, token.confidence))
        let script = script(of: token.text)
        var bonus = 1.0

        switch script {
        case .telugu:
            bonus = token.localeId.hasPrefix("te") ? 1.45 : 0.35
        case .devanagari:
            bonus = token.localeId.hasPrefix("hi") ? 1.45 : 0.35
        case .latin:
            // English inserts: prefer en-US; still allow primary if that's all we have.
            if token.localeId.hasPrefix("en") {
                bonus = 1.4
            } else if token.localeId == primaryLocale {
                bonus = 0.75
            } else {
                bonus = 0.55
            }
        case .other:
            bonus = token.localeId == primaryLocale ? 1.0 : 0.7
        }

        // Prefer slightly longer real words over punctuation crumbs.
        let lengthBoost = min(1.15, 0.9 + Double(token.text.count) * 0.02)
        return conf * bonus * lengthBoost
    }

    private enum ScriptKind { case telugu, devanagari, latin, other }

    nonisolated private static func script(of text: String) -> ScriptKind {
        var te = 0, hi = 0, la = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0C00...0x0C7F: te += 1          // Telugu
            case 0x0900...0x097F: hi += 1          // Devanagari
            case 0x0041...0x005A, 0x0061...0x007A: la += 1
            default: break
            }
        }
        if te >= hi, te >= la, te > 0 { return .telugu }
        if hi >= te, hi >= la, hi > 0 { return .devanagari }
        if la > 0 { return .latin }
        return .other
    }

    // MARK: - Segment grouping

    nonisolated private static func buildSegments(
        from tokens: [TimedToken],
        language: AppLanguage
    ) -> [CaptionSegment] {
        let words = tokens.map {
            CaptionWord(text: $0.text, startTime: $0.startTime, endTime: $0.endTime)
        }
        guard !words.isEmpty else { return [] }

        // Telugu/Hindi lines read better shorter; flush on script change so
        // English inserts don't glue into one unreadable Telugu blob.
        let maxWords = language == .english ? 5 : 4
        var captions: [CaptionSegment] = []
        var buffer: [CaptionWord] = []

        func flush() {
            guard let first = buffer.first, let last = buffer.last else { return }
            let text = buffer.map(\.text).joined(separator: " ")
            captions.append(
                CaptionSegment(
                    text: text,
                    startTime: first.startTime,
                    endTime: max(last.endTime, first.startTime + 0.4),
                    words: buffer
                )
            )
            buffer = []
        }

        for (index, word) in words.enumerated() {
            if let prev = buffer.last {
                if word.startTime - prev.endTime > 0.55 {
                    flush()
                } else if script(of: prev.text) != script(of: word.text),
                          script(of: prev.text) != .other,
                          script(of: word.text) != .other {
                    // Keep short same-phrase mixes (1–2 words) together; longer → new line.
                    if buffer.count >= 2 {
                        flush()
                    }
                }
            }
            buffer.append(word)
            if buffer.count >= maxWords {
                flush()
            }
            if index == words.count - 1 {
                flush()
            }
        }

        return captions
    }

    // MARK: - Audio extract

    private func extractAudio(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { throw TranscriptionError.noAudioTrack }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("captionstudio-audio-\(UUID().uuidString).m4a")

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscriptionError.failed("Could not create audio export session.")
        }
        session.outputURL = outputURL
        session.outputFileType = .m4a

        try await Self.runExport(session)
        return outputURL
    }

    nonisolated private static func runExport(_ session: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: TranscriptionError.failed("Export cancelled."))
                default:
                    continuation.resume(
                        throwing: TranscriptionError.failed(
                            session.error?.localizedDescription ?? "Audio extract failed."
                        )
                    )
                }
            }
        }
    }

    /// Demo captions so the UI is usable without a real speech pass.
    func demoCaptions(for videoURL: URL) -> [CaptionSegment] {
        let duration = Self.quickDuration(of: videoURL)
        let lines = language.demoLines
        let slice = max(duration / Double(lines.count), 1.2)
        return lines.enumerated().map { index, line in
            let start = Double(index) * slice
            let end = min(start + slice * 0.9, duration > 0 ? duration : start + 2)
            let wordParts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            let wordDur = (end - start) / Double(max(wordParts.count, 1))
            let words = wordParts.enumerated().map { wi, w in
                CaptionWord(
                    text: w,
                    startTime: start + Double(wi) * wordDur,
                    endTime: start + Double(wi + 1) * wordDur
                )
            }
            return CaptionSegment(text: line, startTime: start, endTime: end, words: words)
        }
    }

    nonisolated private static func quickDuration(of url: URL) -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        return seconds.isFinite && seconds > 0 ? seconds : 10
    }
}
