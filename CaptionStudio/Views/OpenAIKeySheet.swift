import SwiftUI

/// Focused sheet to paste the OpenAI key before Telugu AI Captions.
struct OpenAIKeySheet: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""
    var onSaved: (() -> Void)?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-… OpenAI API key", text: $draft)
                        #if os(macOS)
                        .textFieldStyle(.roundedBorder)
                        #endif
                    Text("Required for Telugu (+ English) captions. Apple Dictation has no Telugu language. English captions still work without a key.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link("Get an API key at platform.openai.com", destination: URL(string: "https://platform.openai.com/api-keys")!)
                        .font(.footnote)
                } header: {
                    Text("Whisper (Telugu captions)")
                }

                Section {
                    Button("Save key") {
                        editor.apiKeys.openAIAPIKey = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSaved?()
                        dismiss()
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if editor.apiKeys.hasOpenAIKey {
                        Button("Clear saved key", role: .destructive) {
                            draft = ""
                            editor.apiKeys.openAIAPIKey = ""
                        }
                    }
                }
            }
            .navigationTitle("OpenAI API Key")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                draft = editor.apiKeys.openAIAPIKey
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 280)
        #endif
    }
}

/// Compact home-screen row so the key can be set before importing a video.
struct OpenAIKeyHomeBanner: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Binding var showKeySheet: Bool

    var body: some View {
        Button {
            showKeySheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: editor.apiKeys.hasOpenAIKey ? "checkmark.seal.fill" : "key.fill")
                    .foregroundStyle(
                        editor.apiKeys.hasOpenAIKey
                            ? Color(red: 0.2, green: 0.9, blue: 0.7)
                            : Color(red: 1.0, green: 0.85, blue: 0.35)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(editor.apiKeys.hasOpenAIKey ? "OpenAI key saved" : "Add OpenAI key for Telugu captions")
                        .font(.custom("AvenirNext-DemiBold", size: 13))
                        .foregroundStyle(.white)
                    Text(editor.apiKeys.hasOpenAIKey
                          ? "తెలుగు + EN is ready — tap to change key"
                          : "Needed before AI Captions on Telugu videos")
                        .font(.custom("AvenirNext-Medium", size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
