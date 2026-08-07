import SwiftUI

struct BrandKitSettingsView: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Telugu / Hindi captions (Whisper)") {
                    SecureField("OpenAI API key", text: Binding(
                        get: { editor.apiKeys.openAIAPIKey },
                        set: { editor.apiKeys.openAIAPIKey = $0 }
                    ))
                    Text("Apple Dictation has no Telugu. CaptionStudio uses OpenAI Whisper for తెలుగు + EN (and Hindi when hi-IN is missing).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if editor.apiKeys.hasOpenAIKey {
                        Text("Key saved — select తెలుగు + EN, then AI Captions.")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    } else {
                        Text("Get a key at platform.openai.com/api-keys")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Fonts") {
                    TextField("Latin font id", text: Binding(
                        get: { editor.brandKit.kit.primaryFontId },
                        set: { editor.brandKit.kit.primaryFontId = $0 }
                    ))
                    TextField("Hindi font id", text: Binding(
                        get: { editor.brandKit.kit.hindiFontId },
                        set: { editor.brandKit.kit.hindiFontId = $0 }
                    ))
                    TextField("Telugu font id", text: Binding(
                        get: { editor.brandKit.kit.teluguFontId },
                        set: { editor.brandKit.kit.teluguFontId = $0 }
                    ))
                }

                Section("Colors") {
                    TextField("Primary (#RRGGBB)", text: Binding(
                        get: { editor.brandKit.kit.primaryColor },
                        set: { editor.brandKit.kit.primaryColor = $0 }
                    ))
                    TextField("Secondary (#RRGGBB)", text: Binding(
                        get: { editor.brandKit.kit.secondaryColor },
                        set: { editor.brandKit.kit.secondaryColor = $0 }
                    ))
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(editor.brandKit.kit.primarySwiftUIColor)
                            .frame(width: 36, height: 24)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(editor.brandKit.kit.secondarySwiftUIColor)
                            .frame(width: 36, height: 24)
                        Text("Preview")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Defaults") {
                    Picker("Language", selection: Binding(
                        get: { editor.brandKit.kit.appLanguage },
                        set: { editor.brandKit.kit.defaultLanguage = $0.rawValue }
                    )) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.title).tag(lang)
                        }
                    }
                    Picker("Default pack", selection: Binding(
                        get: { editor.brandKit.kit.defaultPackId ?? "" },
                        set: { editor.brandKit.kit.defaultPackId = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("None").tag("")
                        ForEach(editor.packs.packs) { pack in
                            Text(pack.name).tag(pack.id)
                        }
                    }
                    HStack {
                        Text("SFX gain")
                        Slider(value: Binding(
                            get: { editor.brandKit.kit.defaultSfxGain },
                            set: { editor.brandKit.kit.defaultSfxGain = $0 }
                        ), in: 0.2...1.2)
                        Text(String(format: "%.2f", editor.brandKit.kit.defaultSfxGain))
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                Section("Watermark") {
                    Toggle("Burn watermark on export", isOn: Binding(
                        get: { editor.brandKit.kit.watermarkEnabled },
                        set: { editor.brandKit.kit.watermarkEnabled = $0 }
                    ))
                    TextField("Handle / mark", text: Binding(
                        get: { editor.brandKit.kit.watermarkText },
                        set: { editor.brandKit.kit.watermarkText = $0 }
                    ))
                    .disabled(!editor.brandKit.kit.watermarkEnabled)
                }

                Section {
                    Button("Reset to defaults", role: .destructive) {
                        editor.brandKit.reset()
                    }
                    Button("Apply to current project") {
                        editor.applyBrandKitToProject()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Brand Kit")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
