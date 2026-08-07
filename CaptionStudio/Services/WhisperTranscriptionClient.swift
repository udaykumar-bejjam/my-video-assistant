import Foundation

/// OpenAI Whisper transcription for languages Apple Speech does not support (Telugu).
/// Uses `whisper-1` + word timestamps so karaoke / word-hits keep working.
///
/// Important: Whisper auto-detect often mislabels Telugu as **Kannada** (related
/// Dravidian scripts). We always force `language=te` for Telugu and reject
/// Kannada-heavy outputs with one retry.
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
                return "Whisper API error (\(code)): \(body)"
            case .emptyResult:
                return "Whisper returned no speech."
            case .network(let message):
                return message
            case .wrongScript(let detail):
                return detail
            }
        }
    }

    /// Transcribe an audio file into timed words.
    static func transcribe(
        audioURL: URL,
        apiKey: String,
        languageHint: AppLanguage,
        onProgress: (@MainActor (Double, String) -> Void)? = nil
    ) async throws -> [WordStamp] {
        let result = try await transcribeDetailed(
            audioURL: audioURL,
            apiKey: apiKey,
            languageHint: languageHint,
            onProgress: onProgress
        )
        return result.words
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

        await onProgress?(0.4, "Uploading audio to Whisper…")

        // First pass — force Telugu language code so Whisper doesn't pick Kannada.
        var pass = try await runWhisper(
            audioData: audioData,
            filename: filename,
            apiKey: key,
            languageHint: languageHint,
            forceLanguageCode: languageCode(for: languageHint),
            temperature: 0,
            onProgress: onProgress,
            progressLabel: "Whisper pass 1 (\(languageHint.shortLabel)+EN)…"
        )

        if languageHint == .telugu, isKannadaHeavy(pass.words) {
            await onProgress?(0.62, "Whisper returned Kannada — retrying with Telugu lock…")
            pass = try await runWhisper(
                audioData: audioData,
                filename: filename,
                apiKey: key,
                languageHint: languageHint,
                forceLanguageCode: "te",
                temperature: 0,
                strongerTeluguBias: true,
                onProgress: onProgress,
                progressLabel: "Whisper pass 2 (force te)…"
            )
        }

        guard !pass.words.isEmpty else { throw WhisperError.emptyResult }

        if languageHint == .telugu, isKannadaHeavy(pass.words) {
            throw WhisperError.wrongScript(
                "Whisper still produced Kannada script for Telugu audio. Re-run AI Captions, or check the clip is Telugu speech."
            )
        }

        let te = pass.words.filter { script(of: $0.text) == .telugu }.count
        let kn = pass.words.filter { script(of: $0.text) == .kannada }.count
        let la = pass.words.filter { script(of: $0.text) == .latin }.count
        let note = "lang=\(pass.detectedLanguage ?? languageCode(for: languageHint) ?? "?") · TE:\(te) KN:\(kn) EN:\(la)"
        return Result(words: pass.words, detectedLanguage: pass.detectedLanguage, note: note)
    }

    // MARK: - Request

    private struct PassResult {
        var words: [WordStamp]
        var detectedLanguage: String?
    }

    private static func languageCode(for language: AppLanguage) -> String? {
        switch language {
        case .telugu: return "te"
        case .hindi: return "hi"
        case .english: return "en"
        }
    }

    private static func prompt(
        for language: AppLanguage,
        strongerTeluguBias: Bool
    ) -> String {
        switch language {
        case .telugu:
            // Sample Telugu glyphs steer the decoder away from Kannada.
            if strongerTeluguBias {
                return "నమస్కారం ఇది తెలుగు వీడియో. Telugu script only (తెలుగు) — NOT Kannada (ಕನ್ನಡ). English words stay in Latin letters: subscribe, follow, wow, video."
            }
            return "నమస్కారం — తెలుగు మరియు English mixed (Tanglish). Write Telugu words in Telugu script (తెలుగు), never Kannada. Keep English loanwords in Latin script."
        case .hindi:
            return "नमस्ते — हिन्दी और English mixed (Hinglish). Hindi in Devanagari; English words in Latin."
        case .english:
            return "English speech with clear word breaks."
        }
    }

    private static func runWhisper(
        audioData: Data,
        filename: String,
        apiKey: String,
        languageHint: AppLanguage,
        forceLanguageCode: String?,
        temperature: Double,
        strongerTeluguBias: Bool = false,
        onProgress: (@MainActor (Double, String) -> Void)?,
        progressLabel: String
    ) async throws -> PassResult {
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
        appendField("timestamp_granularities[]", "word")
        appendField("temperature", String(temperature))
        appendField("prompt", prompt(for: languageHint, strongerTeluguBias: strongerTeluguBias))
        // Force ISO-639-1 so Telugu isn't auto-detected as Kannada.
        if let forceLanguageCode, !forceLanguageCode.isEmpty {
            appendField("language", forceLanguageCode)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        await onProgress?(0.55, progressLabel)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw WhisperError.network(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "unknown"
            throw WhisperError.badStatus(status, String(bodyText.prefix(280)))
        }

        await onProgress?(0.85, "Parsing word timings…")
        return try parsePass(from: data)
    }

    // MARK: - Script checks

    private enum ScriptKind { case telugu, kannada, devanagari, latin, other }

    private static func script(of text: String) -> ScriptKind {
        var te = 0, kn = 0, hi = 0, la = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0C00...0x0C7F: te += 1   // Telugu
            case 0x0C80...0x0CFF: kn += 1   // Kannada
            case 0x0900...0x097F: hi += 1   // Devanagari
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

    /// True when Kannada glyphs dominate Indic text (Whisper Telugu↔Kannada mix-up).
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
        guard indic >= 3 else { return kn > 0 && te == 0 }
        return kn > te
    }

    // MARK: - Parse

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

    private static func parsePass(from data: Data) throws -> PassResult {
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
                } else if let text = seg.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
                          let start = seg.start, let end = seg.end {
                    let parts = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                    let span = max(0.05, end - start) / Double(max(parts.count, 1))
                    for (i, part) in parts.enumerated() {
                        let s = start + Double(i) * span
                        stamps.append(WordStamp(text: part, start: s, end: s + span))
                    }
                }
            }
        }

        if stamps.isEmpty, let text = decoded.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            let parts = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            for (i, part) in parts.enumerated() {
                let s = Double(i) * 0.4
                stamps.append(WordStamp(text: part, start: s, end: s + 0.35))
            }
        }

        return PassResult(
            words: stamps.sorted { $0.start < $1.start },
            detectedLanguage: decoded.language
        )
    }
}
