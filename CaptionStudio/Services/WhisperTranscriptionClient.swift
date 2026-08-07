import Foundation

/// OpenAI Whisper transcription for languages Apple Speech does not support (Telugu).
/// Uses `whisper-1` + word timestamps so karaoke / word-hits keep working.
enum WhisperTranscriptionClient {
    struct WordStamp: Sendable {
        var text: String
        var start: TimeInterval
        var end: TimeInterval
    }

    enum WhisperError: LocalizedError {
        case missingAPIKey
        case badStatus(Int, String)
        case emptyResult
        case network(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "OpenAI API key required for Telugu captions. Open Brand Kit and paste your key (platform.openai.com)."
            case .badStatus(let code, let body):
                return "Whisper API error (\(code)): \(body)"
            case .emptyResult:
                return "Whisper returned no speech."
            case .network(let message):
                return message
            }
        }
    }

    /// Transcribe an audio file. Leaves language detection open for Telugu+English code-switch.
    static func transcribe(
        audioURL: URL,
        apiKey: String,
        languageHint: AppLanguage,
        onProgress: (@MainActor (Double, String) -> Void)? = nil
    ) async throws -> [WordStamp] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw WhisperError.missingAPIKey }

        await onProgress?(0.4, "Uploading audio to Whisper…")

        let boundary = "CaptionStudio-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180

        let audioData = try Data(contentsOf: audioURL)
        let filename = audioURL.lastPathComponent
        let prompt: String
        switch languageHint {
        case .telugu:
            prompt = "Telugu and English mixed speech (Tanglish). Keep Telugu in Telugu script."
        case .hindi:
            prompt = "Hindi and English mixed speech (Hinglish). Keep Hindi in Devanagari script."
        case .english:
            prompt = "English speech."
        }

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        appendField("model", "whisper-1")
        appendField("response_format", "verbose_json")
        appendField("timestamp_granularities[]", "word")
        // Do NOT force `language=te` — forcing monolingual Telugu hurts English inserts.
        appendField("prompt", prompt)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        await onProgress?(0.55, "Whisper transcribing (\(languageHint.shortLabel)+EN)…")

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
        let words = try parseWords(from: data)
        guard !words.isEmpty else { throw WhisperError.emptyResult }
        return words
    }

    // MARK: - Parse

    private struct VerboseResponse: Decodable {
        var text: String?
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

    private static func parseWords(from data: Data) throws -> [WordStamp] {
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

        // Some responses nest words under segments only.
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
                    // Fall back: split segment text evenly across its time range.
                    let parts = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                    let span = max(0.05, end - start) / Double(max(parts.count, 1))
                    for (i, part) in parts.enumerated() {
                        let s = start + Double(i) * span
                        stamps.append(WordStamp(text: part, start: s, end: s + span))
                    }
                }
            }
        }

        // Last resort: whole transcript, no timings.
        if stamps.isEmpty, let text = decoded.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            let parts = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            for (i, part) in parts.enumerated() {
                let s = Double(i) * 0.4
                stamps.append(WordStamp(text: part, start: s, end: s + 0.35))
            }
        }

        return stamps.sorted { $0.start < $1.start }
    }
}
