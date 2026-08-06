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

/// On-device speech-to-text using Apple's Speech framework.
/// Falls back to a demo transcript when recognition isn't available (simulator / denied).
@MainActor
final class TranscriptionService: ObservableObject {
    @Published var progress: Double = 0
    @Published var statusMessage: String = ""

    private let locale: Locale

    init(locale: Locale = .current) {
        self.locale = locale
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

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            if useDemoFallback {
                statusMessage = "Using demo captions (recognizer unavailable)."
                return demoCaptions(for: videoURL)
            }
            throw TranscriptionError.recognizerUnavailable
        }

        progress = 0.15
        statusMessage = "Extracting audio…"

        let audioURL = try await extractAudio(from: videoURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        progress = 0.35
        statusMessage = "Transcribing with on-device AI…"

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if #available(iOS 16, macOS 13, *) {
            request.addsPunctuation = true
        }

        do {
            let segments = try await recognize(request: request, recognizer: recognizer)
            progress = 1
            statusMessage = "Done — \(segments.count) captions"
            if segments.isEmpty, useDemoFallback {
                statusMessage = "No speech detected — showing demo captions."
                return demoCaptions(for: videoURL)
            }
            return segments
        } catch {
            if useDemoFallback {
                statusMessage = "Transcription failed — using demo captions."
                return demoCaptions(for: videoURL)
            }
            throw TranscriptionError.failed(error.localizedDescription)
        }
    }

    // MARK: - Private

    private func recognize(
        request: SFSpeechURLRecognitionRequest,
        recognizer: SFSpeechRecognizer
    ) async throws -> [CaptionSegment] {
        try await withCheckedThrowingContinuation { continuation in
            final class Box { var task: SFSpeechRecognitionTask?; var hasResumed = false }
            let box = Box()
            box.task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                if let result {
                    let fraction = result.isFinal ? 0.95 : min(0.9, 0.35 + Double(result.bestTranscription.segments.count) * 0.02)
                    Task { @MainActor in
                        self?.progress = fraction
                    }
                    if result.isFinal, !box.hasResumed {
                        box.hasResumed = true
                        continuation.resume(returning: Self.buildSegments(from: result.bestTranscription))
                    }
                } else if let error, !box.hasResumed {
                    box.hasResumed = true
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    nonisolated private static func buildSegments(
        from transcription: SFTranscription
    ) -> [CaptionSegment] {
        let words = transcription.segments.map { seg in
            CaptionWord(
                text: seg.substring,
                startTime: seg.timestamp,
                endTime: seg.timestamp + max(seg.duration, 0.08)
            )
        }

        guard !words.isEmpty else { return [] }

        // Group into phrase-sized captions (~4–6 words or natural pauses).
        var captions: [CaptionSegment] = []
        var buffer: [CaptionWord] = []
        let maxWords = 5

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
            if let prev = buffer.last, word.startTime - prev.endTime > 0.55 {
                flush()
            }
            buffer.append(word)
            if buffer.count >= maxWords {
                flush()
            }
            // End of list
            if index == words.count - 1 {
                flush()
            }
        }

        return captions
    }

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
        let lines = [
            "Hey — welcome to CaptionStudio",
            "AI captions in one tap",
            "Pick a style that pops",
            "Add overlays and emojis",
            "Export ready for social"
        ]
        let slice = max(duration / Double(lines.count), 1.2)
        return lines.enumerated().map { index, line in
            let start = Double(index) * slice
            let end = min(start + slice * 0.9, duration > 0 ? duration : start + 2)
            let wordParts = line.split(separator: " ").map(String.init)
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
