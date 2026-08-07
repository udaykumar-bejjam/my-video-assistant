import Foundation
import AVFoundation
import Speech
import Combine

enum TranscriptionError: LocalizedError {
    case noAudioTrack
    case authorizationDenied
    case recognizerUnavailable
    case primaryLocaleUnavailable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack: return "This video has no audio track to transcribe."
        case .authorizationDenied: return "Speech recognition permission was denied."
        case .recognizerUnavailable: return "Speech recognition is unavailable on this device."
        case .primaryLocaleUnavailable(let id):
            return "\(id) speech recognition is not available. On macOS: System Settings → Keyboard → Dictation, enable Dictation and download the Telugu / Hindi language. Then retry AI Captions."
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
/// For Telugu/Hindi + English code-switching:
/// 1. Run primary locale (`te-IN` / `hi-IN`) as the **backbone** transcript
/// 2. Run `en-US` only to recover clear English inserts
/// 3. Never let English overwrite Telugu/Devanagari script tokens
///
/// The previous winner-takes-all merge preferred high-confidence English
/// hallucinations over real Telugu audio — captions became English-only.
@MainActor
final class TranscriptionService: ObservableObject {
    @Published var progress: Double = 0
    @Published var statusMessage: String = ""

    var language: AppLanguage = .english
    /// OpenAI key for Whisper (Telugu / Hindi when Apple Speech has no pack).
    var openAIAPIKey: String = ""
    /// Authoritative video timeline from the editor (floor for ASR timing).
    /// Prevents packing captions into a short/wrong asset duration.
    var knownTimelineDuration: TimeInterval = 0

    init(language: AppLanguage = .english) {
        self.language = language
    }

    /// Telugu is not in Apple Dictation on most Macs — always use Whisper.
    /// Hindi uses Whisper when `hi-IN` is unavailable.
    private var prefersWhisper: Bool {
        switch language {
        case .telugu:
            return true
        case .hindi:
            return Self.makeRecognizer(for: "hi-IN") == nil
        case .english:
            return false
        }
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

        // Telugu (and Hindi without Apple pack) → OpenAI Whisper.
        if prefersWhisper {
            return try await transcribeWithWhisper(videoURL: videoURL, useDemoFallback: useDemoFallback)
        }

        statusMessage = "Checking permissions…"

        let status = await requestAuthorization()
        guard status == .authorized || status == .notDetermined else {
            if useDemoFallback {
                statusMessage = "Using demo captions (speech permission denied)."
                return demoCaptions(for: videoURL)
            }
            throw TranscriptionError.authorizationDenied
        }

        let primaryId = language.localeIdentifier
        let companionIds = language.transcriptionLocaleIdentifiers.filter { $0 != primaryId }

        guard let primaryRecognizer = Self.makeRecognizer(for: primaryId) else {
            // Fall through to Whisper if we have a key (e.g. rare EN locale miss).
            if !openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return try await transcribeWithWhisper(videoURL: videoURL, useDemoFallback: useDemoFallback)
            }
            throw TranscriptionError.primaryLocaleUnavailable(primaryId)
        }

        var recognizers: [(String, SFSpeechRecognizer)] = [(primaryId, primaryRecognizer)]
        for id in companionIds {
            if let r = Self.makeRecognizer(for: id) {
                recognizers.append((id, r))
            }
        }

        progress = 0.15
        statusMessage = "Extracting audio…"

        let audioURL = try await extractAudio(from: videoURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        do {
            var primaryTokens: [TimedToken] = []
            var englishTokens: [TimedToken] = []
            var passNotes: [String] = []

            for (index, pair) in recognizers.enumerated() {
                let (localeId, recognizer) = pair
                progress = 0.28 + 0.35 * Double(index) / Double(max(recognizers.count, 1))
                statusMessage = "Pass \(index + 1)/\(recognizers.count): \(localeId)…"
                do {
                    let tokens = try await recognizeTokens(
                        audioURL: audioURL,
                        localeId: localeId,
                        recognizer: recognizer
                    )
                    if localeId == primaryId || localeId.hasPrefix(String(primaryId.prefix(2))) {
                        // Keep the richest primary pass if we tried aliases.
                        if tokens.count >= primaryTokens.count { primaryTokens = tokens }
                    } else if localeId.hasPrefix("en") {
                        englishTokens = tokens
                    }
                    passNotes.append("\(localeId):\(tokens.count)")
                } catch {
                    passNotes.append("\(localeId):fail")
                    // Primary failure is fatal for TE/HI — don't fall through to English-only.
                    if localeId == primaryId {
                        throw error
                    }
                }
            }

            if primaryTokens.isEmpty {
                statusMessage = "No \(language.shortLabel) speech decoded (\(passNotes.joined(separator: ", ")))."
                if useDemoFallback {
                    statusMessage += " Showing demo captions."
                    return demoCaptions(for: videoURL)
                }
                return []
            }

            let merged: [TimedToken]
            if englishTokens.isEmpty || language == .english {
                merged = primaryTokens.sorted { $0.startTime < $1.startTime }
            } else {
                merged = Self.mergePrimaryWithEnglish(
                    primary: primaryTokens,
                    english: englishTokens,
                    primaryLocale: primaryId
                )
            }

            let segments = Self.buildSegments(from: merged, language: language)
            // Apple Speech has real clocks — only hold lines longer, don't stretch to full video.
            let timeline = max(
                knownTimelineDuration,
                await Self.loadDuration(of: videoURL),
                await Self.loadDuration(of: audioURL),
                segments.last?.endTime ?? 1,
                1
            )
            let paced = Self.paceCaptionsToTimeline(
                segments,
                timelineDuration: timeline,
                language: language,
                stretchToFullTimeline: false
            )
            progress = 1

            if paced.isEmpty {
                if useDemoFallback {
                    statusMessage = "No speech detected — showing demo captions."
                    return demoCaptions(for: videoURL)
                }
                return []
            }

            let teCount = merged.filter { Self.script(of: $0.text) == .telugu }.count
            let hiCount = merged.filter { Self.script(of: $0.text) == .devanagari }.count
            let laCount = merged.filter { Self.script(of: $0.text) == .latin }.count
            statusMessage = "Done — \(paced.count) captions · \(passNotes.joined(separator: " · ")) · TE:\(teCount) HI:\(hiCount) EN:\(laCount)"
            return paced
        } catch {
            if useDemoFallback {
                statusMessage = "Transcription failed — using demo captions. (\(error.localizedDescription))"
                return demoCaptions(for: videoURL)
            }
            throw TranscriptionError.failed(error.localizedDescription)
        }
    }

    /// Resolve a recognizer, trying common locale alias spellings.
    nonisolated private static func makeRecognizer(for localeId: String) -> SFSpeechRecognizer? {
        var candidates = [localeId]
        // Apple sometimes registers `te` / `te_IN` instead of `te-IN`.
        if localeId.contains("-") {
            candidates.append(localeId.replacingOccurrences(of: "-", with: "_"))
            candidates.append(String(localeId.prefix(2)))
        }
        for id in candidates {
            let locale = Locale(identifier: id)
            if let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable {
                return recognizer
            }
        }
        // Last resort: any supported locale with the same language code.
        let prefix = String(localeId.prefix(2)).lowercased()
        for locale in SFSpeechRecognizer.supportedLocales() where locale.identifier.lowercased().hasPrefix(prefix) {
            if let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable {
                return recognizer
            }
        }
        return nil
    }

    // MARK: - Whisper (Telugu / multilingual)

    private func transcribeWithWhisper(
        videoURL: URL,
        useDemoFallback: Bool
    ) async throws -> [CaptionSegment] {
        let key = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            statusMessage = "OpenAI API key required for \(language.shortLabel) captions."
            throw TranscriptionError.failed(
                "Telugu is not available in Apple Dictation. Add an OpenAI API key in Brand Kit, then tap AI Captions again."
            )
        }

        progress = 0.12
        statusMessage = "Extracting audio for Whisper…"
        let audioURL = try await extractAudio(from: videoURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        // Prefer editor-known duration + source video. Never trust a short M4A alone —
        // packing the full transcript into ~10s makes captions/hits race ahead of A/V.
        let timelineDuration = max(
            knownTimelineDuration,
            await Self.loadDuration(of: videoURL),
            await Self.loadDuration(of: audioURL),
            1
        )

        do {
            let result = try await WhisperTranscriptionClient.transcribeDetailed(
                audioURL: audioURL,
                apiKey: key,
                languageHint: language,
                timelineDuration: timelineDuration
            ) { [weak self] value, message in
                self?.progress = value
                self?.statusMessage = message
            }

            // Keep estimated clocks as-is; only compress if they overrun the video
            // (do NOT stretch to fill the full timeline — that made captions appear late).
            let remapped = WhisperTranscriptionClient.clampWordsToTimeline(
                result.words,
                duration: timelineDuration
            )
            let tokens = remapped.map {
                TimedToken(
                    text: $0.text,
                    startTime: $0.start,
                    endTime: $0.end,
                    confidence: 1,
                    localeId: "whisper"
                )
            }
            var segments = Self.buildSegments(from: tokens, language: language)
            segments = Self.paceCaptionsToTimeline(
                segments,
                timelineDuration: timelineDuration,
                language: language,
                stretchToFullTimeline: false
            )
            progress = 1
            guard !segments.isEmpty else {
                if useDemoFallback {
                    statusMessage = "Whisper returned empty — demo captions."
                    return demoCaptions(for: videoURL)
                }
                return []
            }
            let last = segments.last?.endTime ?? 0
            statusMessage = "Whisper done — \(segments.count) captions · \(String(format: "%.1fs", last))/\(String(format: "%.1fs", timelineDuration)) · \(result.note ?? "")"
            return segments
        } catch {
            if useDemoFallback {
                statusMessage = "Whisper failed — demo captions. (\(error.localizedDescription))"
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

    // MARK: - Code-switch merge (primary backbone)

    /// Keep primary-language tokens as the timeline. Only splice English where it
    /// fills a gap or clearly beats a weak *non-native-script* primary token.
    nonisolated private static func mergePrimaryWithEnglish(
        primary: [TimedToken],
        english: [TimedToken],
        primaryLocale: String
    ) -> [TimedToken] {
        var result = primary.sorted { $0.startTime < $1.startTime }
        let primaryScript: ScriptKind = primaryLocale.hasPrefix("te")
            ? .telugu
            : (primaryLocale.hasPrefix("hi") ? .devanagari : .other)

        let englishCandidates = english
            .filter { script(of: $0.text) == .latin }
            .filter { $0.confidence >= 0.25 }
            .filter { isPlausibleEnglishInsert($0.text) }
            .sorted { $0.startTime < $1.startTime }

        for en in englishCandidates {
            if let idx = result.firstIndex(where: { overlapsTight($0, en) }) {
                let existing = result[idx]
                let existingScript = script(of: existing.text)

                // Never overwrite native-script words with English hallucinations.
                if existingScript == primaryScript { continue }
                if existingScript == .telugu || existingScript == .devanagari { continue }

                // Replace weak Latin / other primary token only if English is stronger.
                let enScore = Double(en.confidence) * 1.15
                let existingScore = Double(max(0.05, existing.confidence))
                    * (existingScript == .latin ? 0.9 : 0.6)
                if enScore > existingScore {
                    result[idx] = en
                }
            } else if isGap(for: en, in: result) {
                // Insert English into a real silence / coverage hole in the primary pass.
                result.append(en)
                result.sort { $0.startTime < $1.startTime }
            }
        }

        return result
    }

    /// True when primary has no token covering most of this English window.
    nonisolated private static func isGap(for en: TimedToken, in primary: [TimedToken]) -> Bool {
        let mid = (en.startTime + en.endTime) / 2
        let covered = primary.contains { token in
            mid >= token.startTime - 0.05 && mid <= token.endTime + 0.05
        }
        if covered { return false }
        // Also require a little breathing room so we don't double-caption edges.
        let near = primary.contains { token in
            abs(token.startTime - en.startTime) < 0.12
        }
        return !near
    }

    nonisolated private static func overlapsTight(_ a: TimedToken, _ b: TimedToken) -> Bool {
        let start = max(a.startTime, b.startTime)
        let end = min(a.endTime, b.endTime)
        let overlap = end - start
        guard overlap > 0 else { return abs(a.startTime - b.startTime) < 0.1 }
        let shorter = max(0.05, min(a.endTime - a.startTime, b.endTime - b.startTime))
        return overlap >= shorter * 0.55
    }

    /// Filter out English ASR crumbs / phoneme soup that isn't a real insert.
    nonisolated private static func isPlausibleEnglishInsert(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’().,!?…:;"))
        guard cleaned.count >= 2, cleaned.count <= 24 else { return false }
        let letters = cleaned.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard letters.count >= 2 else { return false }
        // Must be mostly Latin letters.
        let latin = letters.filter {
            (0x0041...0x005A).contains($0.value) || (0x0061...0x007A).contains($0.value)
        }
        return latin.count * 2 >= letters.count
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

        // Fewer cuts = each line stays on screen longer (reads with speech, not ahead).
        let maxWords = language == .english ? 6 : 5
        var captions: [CaptionSegment] = []
        var buffer: [CaptionWord] = []

        func flush() {
            guard let first = buffer.first, let last = buffer.last else { return }
            let text = buffer.map(\.text).joined(separator: " ")
            // Keep each phrase readable — Telugu lines need more on-screen time.
            let minHold = language == .english ? 0.9 : 1.6
            captions.append(
                CaptionSegment(
                    text: text,
                    startTime: first.startTime,
                    endTime: max(last.endTime, first.startTime + minHold),
                    words: buffer
                )
            )
            buffer = []
        }

        for (index, word) in words.enumerated() {
            if let prev = buffer.last {
                if word.startTime - prev.endTime > 0.85 {
                    flush()
                } else if script(of: prev.text) != script(of: word.text),
                          script(of: prev.text) != .other,
                          script(of: word.text) != .other,
                          buffer.count >= 2 {
                    flush()
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

    /// Hold each caption until the next one starts (extends end only — never delays starts).
    /// `stretchToFullTimeline` is intentionally unused/false: expanding starts to fill the
    /// video made on-video captions lag behind speech while the word list still looked fine.
    nonisolated private static func paceCaptionsToTimeline(
        _ captions: [CaptionSegment],
        timelineDuration: TimeInterval,
        language: AppLanguage,
        stretchToFullTimeline: Bool = false
    ) -> [CaptionSegment] {
        guard !captions.isEmpty, timelineDuration > 0.5 else { return captions }
        var paced = captions.sorted { $0.startTime < $1.startTime }

        // Anticipation so estimated / aligned clocks don't sit 1–2s behind speech.
        let lead = language == .english ? 0.25 : 0.45
        paced = paced.map { cap in
            var copy = cap
            copy.startTime = max(0, cap.startTime - lead)
            copy.endTime = max(copy.startTime + 0.2, cap.endTime - lead)
            copy.words = cap.words.map { word in
                CaptionWord(
                    text: word.text,
                    startTime: max(0, word.startTime - lead),
                    endTime: max(word.startTime - lead + 0.08, word.endTime - lead)
                )
            }
            return copy
        }

        // Compress only if the track overruns the video (never expand / delay starts).
        if let last = paced.last, last.endTime > timelineDuration + 0.05 {
            let srcStart = paced.first!.startTime
            let srcEnd = last.endTime
            let srcSpan = max(0.1, srcEnd - srcStart)
            let dstSpan = max(0.5, timelineDuration - srcStart)
            paced = paced.map { cap in
                let a = (cap.startTime - srcStart) / srcSpan
                let b = (cap.endTime - srcStart) / srcSpan
                var copy = cap
                copy.startTime = srcStart + a * dstSpan
                copy.endTime = srcStart + max(a + 0.08, b) * dstSpan
                copy.words = cap.words.map { word in
                    let wa = (word.startTime - srcStart) / srcSpan
                    let wb = (word.endTime - srcStart) / srcSpan
                    return CaptionWord(
                        text: word.text,
                        startTime: srcStart + wa * dstSpan,
                        endTime: srcStart + max(wa + 0.05, wb) * dstSpan
                    )
                }
                return copy
            }
        }

        // Hold each line until the next begins (readability) — does not move startTimes.
        for i in 0..<paced.count {
            let minHold = language == .english ? 0.85 : 1.35
            let holdEnd = max(paced[i].endTime, paced[i].startTime + minHold)
            if i + 1 < paced.count {
                paced[i].endTime = min(timelineDuration, max(holdEnd, paced[i + 1].startTime - 0.04))
                // Avoid overlapping the next caption start.
                paced[i].endTime = min(paced[i].endTime, paced[i + 1].startTime - 0.02)
                paced[i].endTime = max(paced[i].endTime, paced[i].startTime + 0.2)
            } else {
                paced[i].endTime = min(timelineDuration, holdEnd)
            }
            // Keep word clocks proportional inside the held window without shifting the phrase start.
            if !paced[i].words.isEmpty {
                let w0 = paced[i].words.first!.startTime
                let w1 = max(paced[i].words.last!.endTime, w0 + 0.05)
                let srcSpan = max(0.05, w1 - w0)
                let dstStart = paced[i].startTime
                let dstSpan = max(0.05, paced[i].endTime - paced[i].startTime)
                paced[i].words = paced[i].words.map { word in
                    let local0 = (word.startTime - w0) / srcSpan
                    let local1 = (word.endTime - w0) / srcSpan
                    return CaptionWord(
                        text: word.text,
                        startTime: dstStart + local0 * dstSpan,
                        endTime: dstStart + max(local0 + 0.05, local1) * dstSpan
                    )
                }
            }
        }

        _ = stretchToFullTimeline // reserved; expanding to full video caused late on-timeline captions
        return paced
    }

    nonisolated private static func loadDuration(of url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            if seconds.isFinite, seconds > 0.2 { return seconds }
        } catch {
            let seconds = CMTimeGetSeconds(asset.duration)
            if seconds.isFinite, seconds > 0.2 { return seconds }
        }
        return 0
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
