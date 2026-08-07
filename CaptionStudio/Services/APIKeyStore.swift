import Foundation
import Combine

/// Stores the OpenAI API key used for Whisper Telugu/Hindi captions.
/// Kept separate from BrandKit so keys aren't mixed into creative defaults.
@MainActor
final class APIKeyStore: ObservableObject {
    @Published var openAIAPIKey: String {
        didSet { UserDefaults.standard.set(openAIAPIKey, forKey: Self.openAIKey) }
    }

    private static let openAIKey = "CaptionStudio.OpenAIAPIKey"

    init() {
        // Prefer saved UI value; fall back to process env for local debug builds.
        if let saved = UserDefaults.standard.string(forKey: Self.openAIKey), !saved.isEmpty {
            openAIAPIKey = saved
        } else if let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !env.isEmpty {
            openAIAPIKey = env
        } else {
            openAIAPIKey = ""
        }
    }

    var hasOpenAIKey: Bool {
        !openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var trimmedOpenAIKey: String {
        openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
