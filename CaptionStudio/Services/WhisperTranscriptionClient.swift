import Foundation
import AVFoundation

/// OpenAI speech-to-text for Telugu (Apple has no te-IN Dictation).
///
/// Critical API fact: hosted **whisper-1 does NOT support `language=te`**
/// (Telugu). It *does* support Kannada (`kn`), which is why auto-detect
/// produced Kannada captions. For Telugu we use **gpt-transcribe** with
/// `languages[]=te` + `languages[]=en` (code-switch), then estimate word
/// timings from audio duration (gpt-transcribe has no word timestamps).
enum WhisperTranscriptionClient {
    struct WordStamp: Sendable {
        var text: String
        var start: TimeInterval
        var end: TimeInterval
    }

    struct Result: Sendable {
        var words: [WordStamp]
        var detectedLanguage: String?
        var note: String?
    }

    enum WhisperError: LocalizedError {
        case missingAPIKey
        case badStatus(Int, String)
        case emptyResult
        case network(String)
        case wrongScript(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "OpenAI API key required for Telugu captions. Tap Add API Key, then retry AI Captions."
            case .badStatus(let code, let body):
                return "Transcription API error (\(code)): \(body)"
            case .emptyResult:
                return "Transcription returned no speech."
            case .network(let message):
                return message
            case .wrongScript(let detail):
                return detail
            }
        }
    }

    static func transcribe(
        audioURL: URL,
        apiKey: String,
        languageHint: AppLanguage,
        onProgress: (@MainActor (Double, String) -> Void)? = nil
    ) async throws -> [WordStamp] {
        try await transcribeDetailed(
            audioURL: audioURL,
            apiKey: apiKey,
            languageHint: languageHint,
            onProgress: onProgress
        ).words
    }

    static func transcribeDetailed(
        audioURL: URL,
        apiKey: String,
        languageHint: AppLanguage,
        onProgress: (@MainActor (Double, String) -> Void)? = nil
    ) async throws -> Result {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw WhisperError.missingAPIKey }

        let audioData = try Data(contentsOf: audioURL)
        let filename = audioURL.lastPathComponent
        let duration = max(0.5, audioDuration(url: audioURL))

        await onProgress?(0.35, "Uploading audio…")

        switch languageHint {
        case .telugu:
            return try await transcribeTelugu(
                audioData: audioData,
                filename: filename,
                apiKey: key,
                duration: duration,
                onProgress: onProgress
            )
        case .hindi, .english:
            // Hindi/English: whisper-1 supports hi/en + word timestamps.
            return try await transcribeWithWhisper1(
                audioData: audioData,
                filename: filename,
                apiKey: key,
                languageHint: languageHint,
                duration: duration,
                onProgress: onProgress
            )
        }
    }

    // MARK: - Telugu (gpt-transcribe)

    private static func transcribeTelugu(
        audioData: Data,
        filename: String,
        apiKey: String,
        duration: TimeInterval,
        onProgress: (@MainActor (Double, String) -> Void)?
    ) async throws -> Result {
        await onProgress?(0.5, "gpt-transcribe (తెలుగు + EN)…")

        // Prefer gpt-transcribe — supports Telugu; whisper-1 does not accept language=te.
        do {
            let text = try await runGPTTranscribe(
                audioData: audioData,
                filename: filename,
                apiKey: apiKey,
                languages: ["te", "en"],
                prompt: teluguPrompt(strong: false)
            )
            var words = stampWords(from: text, duration: duration)
            if isKannadaHeavy(words) {
                await onProgress?(0.65, "Kannada script detected — retrying stronger Telugu bias…")
                let retry = try await runGPTTranscribe(
                    audioData: audioData,
                    filename: filename,
                    apiKey: apiKey,
                    languages: ["te", "en"],
                    prompt: teluguPrompt(strong: true)
                )
                words = stampWords(from: retry, duration: duration)
            }
            if isKannadaHeavy(words) {
                throw WhisperError.wrongScript(
                    "Model returned Kannada script for Telugu audio. Retry AI Captions; if it persists the clip may be mis-labeled."
                )
            }
            let te = words.filter { script(of: $0.text) == .telugu }.count
            let kn = words.filter { script(of: $0.text) == .kannada }.count
            let la = words.filter { script(of: $0.text) == .latin }.count
            return Result(
                words: words,
                detectedLanguage: "te+en",
                note: "gpt-transcribe · TE:\(te) KN:\(kn) EN:\(la)"
            )
        } catch let err as WhisperError {
            if case .badStatus(400, let body) = err,
               body.localizedCaseInsensitiveContains("language")
                || body.localizedCaseInsensitiveContains("unsupported") {
                // Older accounts / model without te in languages[] — prompt-only whisper fallback.
                await onProgress?(0.6, "gpt-transcribe rejected te — Whisper prompt fallback…")
                return try await teluguWhisperPromptOnly(
                    audioData: audioData,
                    filename: filename,
                    apiKey: apiKey,
                    duration: duration,
                    onProgress: onProgress
                )
            }
            throw err
        }
    }

    /// whisper-1 cannot force te; omit language and steer with Telugu prompt only.
    private static func teluguWhisperPromptOnly(
        audioData: Data,
        filename: String,
        apiKey: String,
        duration: TimeInterval,
        onProgress: (@MainActor (Double, String) -> Void)?
    ) async throws -> Result {
        var pass = try await runWhisper1(
            audioData: audioData,
            filename: filename,
            apiKey: apiKey,
            languageCode: nil, // never send "te" — API 400s
            prompt: teluguPrompt(strong: true),
            wantWordTimestamps: true
        )
        if isKannadaHeavy(pass.words) {
            await onProgress?(0.75, "Whisper→Kannada — taking text-only Telugu prompt pass…")
            // Second try: no timestamps, still prompt-only (same limitation).
            pass = try await runWhisper1(
                audioData: audioData,
                filename: filename,
                apiKey: apiKey,
                languageCode: nil,
                prompt: teluguPrompt(strong: true),
                wantWordTimestamps: false
            )
            if pass.words.isEmpty, let text = pass.fullText {
                pass.words = stampWords(from: text, duration: duration)
            }
        }
        if isKannadaHeavy(pass.words) {
            throw WhisperError.wrongScript(
                "OpenAI whisper-1 does not officially support Telugu and fell back to Kannada. Try again later or use a Telugu-capable model (gpt-transcribe)."
            )
        }
        let te = pass.words.filter { script(of: $0.text) == .telugu }.count
        let kn = pass.words.filter { script(of: $0.text) == .kannada }.count
        let la = pass.words.filter { script(of: $0.text) == .latin }.count
        return Result(
            words: pass.words,
            detectedLanguage: pass.detectedLanguage,
            note: "whisper-1 prompt-only · TE:\(te) KN:\(kn) EN:\(la)"
        )
    }

    private static func teluguPrompt(strong: Bool) -> String {
        if strong {
            return "నమస్కారం ఇది తెలుగు వీడియో. Write ONLY Telugu script (తెలుగు) for Telugu words — NEVER Kannada (ಕನ್ನಡ). English words in Latin: subscribe, follow, wow, video, Instagram."
        }
        return "నమస్కారం — తెలుగు మరియు English mixed (Tanglish). Telugu words in Telugu script (తెలుగు), not Kannada. English loanwords in Latin letters."
    }

    // MARK: - Hindi / English whisper-1

    private static func transcribeWithWhisper1(
        audioData: Data,
        filename: String,
        apiKey: String,
        languageHint: AppLanguage,
        duration: TimeInterval,
        onProgress: (@MainActor (Double, String) -> Void)?
    ) async throws -> Result {
        await onProgress?(0.55, "whisper-1 (\(languageHint.shortLabel))…")
        let code: String? = languageHint == .hindi ? "hi" : "en"
        let prompt = languageHint == .hindi
            ? "नमस्ते — हिन्दी और English mixed. Hindi in Devanagari; English in Latin."
            : "English speech with clear word breaks."
        let pass = try await runWhisper1(
            audioData: audioData,
            filename: filename,
            apiKey: apiKey,
            languageCode: code,
            prompt: prompt,
            wantWordTimestamps: true
        )
        var words = pass.words
        if words.isEmpty, let text = pass.fullText {
            words = stampWords(from: text, duration: duration)
        }
        guard !words.isEmpty else { throw WhisperError.emptyResult }
        return Result(
            words: words,
            detectedLanguage: pass.detectedLanguage ?? code,
            note: "whisper-1 · \(words.count) words"
        )
    }

    // MARK: - HTTP

    private struct WhisperPass {
        var words: [WordStamp]
        var fullText: String?
        var detectedLanguage: String?
    }

    private static func runGPTTranscribe(
        audioData: Data,
        filename: String,
        apiKey: String,
        languages: [String],
        prompt: String
    ) async throws -> String {
        let boundary = "CaptionStudio-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        appendField("model", "gpt-transcribe")
        appendField("response_format", "json")
        appendField("temperature", "0")
        appendField("prompt", prompt)
        for lang in languages {
            appendField("languages[]", lang)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw WhisperError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "unknown"
            throw WhisperError.badStatus(status, String(bodyText.prefix(400)))
        }
        // gpt-transcribe returns { "text": "..." }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = obj["text"] as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        throw WhisperError.emptyResult
    }

    private static func runWhisper1(
        audioData: Data,
        filename: String,
        apiKey: String,
        languageCode: String?,
        prompt: String,
        wantWordTimestamps: Bool
    ) async throws -> WhisperPass {
        let boundary = "CaptionStudio-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        appendField("model", "whisper-1")
        appendField("response_format", "verbose_json")
        appendField("temperature", "0")
        appendField("prompt", prompt)
        if wantWordTimestamps {
            appendField("timestamp_granularities[]", "word")
        }
        // Only send language when OpenAI lists it (hi/en/kn…). Never "te".
        if let languageCode, languageCode != "te" {
            appendField("language", languageCode)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw WhisperError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "unknown"
            throw WhisperError.badStatus(status, String(bodyText.prefix(400)))
        }
        return try parseWhisperPass(from: data)
    }

    // MARK: - Timing helpers

    private static func audioDuration(url: URL) -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        return seconds.isFinite && seconds > 0 ? seconds : 10
    }

    /// Approximate word timings when the model returns text only (gpt-transcribe).
    private static func stampWords(from text: String, duration: TimeInterval) -> [WordStamp] {
        let parts = text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return [] }
        let weights = parts.map { max(1.0, Double($0.count)) }
        let totalWeight = weights.reduce(0, +)
        var t = 0.0
        var stamps: [WordStamp] = []
        for (i, part) in parts.enumerated() {
            let span = duration * (weights[i] / totalWeight)
            let end = i == parts.count - 1 ? duration : min(duration, t + max(0.08, span))
            stamps.append(WordStamp(text: part, start: t, end: max(t + 0.05, end)))
            t = end
        }
        return stamps
    }

    // MARK: - Script

    private enum ScriptKind { case telugu, kannada, devanagari, latin, other }

    private static func script(of text: String) -> ScriptKind {
        var te = 0, kn = 0, hi = 0, la = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0C00...0x0C7F: te += 1
            case 0x0C80...0x0CFF: kn += 1
            case 0x0900...0x097F: hi += 1
            case 0x0041...0x005A, 0x0061...0x007A: la += 1
            default: break
            }
        }
        let maxIndic = max(te, kn, hi)
        if maxIndic > 0 {
            if te >= kn, te >= hi { return .telugu }
            if kn >= te, kn >= hi { return .kannada }
            if hi >= te, hi >= kn { return .devanagari }
        }
        if la > 0 { return .latin }
        return .other
    }

    private static func isKannadaHeavy(_ words: [WordStamp]) -> Bool {
        var te = 0, kn = 0
        for w in words {
            switch script(of: w.text) {
            case .telugu: te += 1
            case .kannada: kn += 1
            default: break
            }
        }
        let indic = te + kn
        guard indic >= 2 else { return kn > 0 && te == 0 }
        return kn > te
    }

    // MARK: - Parse whisper verbose_json

    private struct VerboseResponse: Decodable {
        var text: String?
        var language: String?
        var words: [WordDTO]?
        var segments: [SegmentDTO]?
    }

    private struct WordDTO: Decodable {
        var word: String?
        var start: Double?
        var end: Double?
    }

    private struct SegmentDTO: Decodable {
        var text: String?
        var start: Double?
        var end: Double?
        var words: [WordDTO]?
    }

    private static func parseWhisperPass(from data: Data) throws -> WhisperPass {
        let decoded = try JSONDecoder().decode(VerboseResponse.self, from: data)
        var stamps: [WordStamp] = []

        if let words = decoded.words, !words.isEmpty {
            stamps = words.compactMap { w in
                guard let text = w.word?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
                      let start = w.start, let end = w.end
                else { return nil }
                return WordStamp(text: text, start: start, end: max(end, start + 0.05))
            }
        }

        if stamps.isEmpty, let segments = decoded.segments {
            for seg in segments {
                if let words = seg.words, !words.isEmpty {
                    for w in words {
                        guard let text = w.word?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
                              let start = w.start, let end = w.end
                        else { continue }
                        stamps.append(WordStamp(text: text, start: start, end: max(end, start + 0.05)))
                    }
                }
            }
        }

        return WhisperPass(
            words: stamps.sorted { $0.start < $1.start },
            fullText: decoded.text,
            detectedLanguage: decoded.language
        )
    }
}
