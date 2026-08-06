import SwiftUI

/// Lists silence / filler trim suggestions with confirm-to-apply.
struct TrimAssistView: View {
    @EnvironmentObject private var editor: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Trim assist")
                    .font(.custom("AvenirNext-Bold", size: 15))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    editor.refreshTrimSuggestions()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            if editor.project.captions.isEmpty {
                Text("Generate captions first to detect silence and fillers.")
                    .font(.custom("AvenirNext-Medium", size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 16)
            } else if editor.trimSuggestions.isEmpty {
                Text("No silence or filler gaps found.")
                    .font(.custom("AvenirNext-Medium", size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 16)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(editor.trimSuggestions) { suggestion in
                            let on = editor.selectedTrimIDs.contains(suggestion.id)
                            Button {
                                editor.toggleTrimSuggestion(suggestion.id)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(on ? Color(red: 1.0, green: 0.75, blue: 0.3) : .white.opacity(0.35))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(suggestion.reason.capitalized)
                                            .font(.custom("AvenirNext-DemiBold", size: 13))
                                            .foregroundStyle(.white)
                                        Text(String(
                                            format: "%.2fs – %.2fs · %.2fs",
                                            suggestion.startTime,
                                            suggestion.endTime,
                                            suggestion.duration
                                        ))
                                        .font(.custom("AvenirNext-Medium", size: 11))
                                        .foregroundStyle(.white.opacity(0.45))
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(Color.white.opacity(on ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Button {
                    Task { await editor.applySelectedTrims() }
                } label: {
                    Label(
                        editor.isTrimming
                        ? "Trimming…"
                        : "Apply \(editor.selectedTrimIDs.count) trim(s)",
                        systemImage: "scissors"
                    )
                    .font(.custom("AvenirNext-DemiBold", size: 14))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(red: 1.0, green: 0.75, blue: 0.3), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(editor.isTrimming || editor.selectedTrimIDs.isEmpty)
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 8)
        .onAppear {
            if editor.trimSuggestions.isEmpty, !editor.project.captions.isEmpty {
                editor.refreshTrimSuggestions()
            }
        }
    }
}
