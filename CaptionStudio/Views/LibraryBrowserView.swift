import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct LibraryBrowserView: View {
    @EnvironmentObject private var editor: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Asset libraries")
                    .font(.custom("AvenirNext-Bold", size: 15))
                    .foregroundStyle(.white)
                Spacer()
                enhanceButton
            }
            .padding(.horizontal, 16)

            if let note = editor.lastEnhancementNote {
                Text(note)
                    .font(.custom("AvenirNext-Medium", size: 11))
                    .foregroundStyle(Color(red: 0.4, green: 0.95, blue: 0.8).opacity(0.85))
                    .padding(.horizontal, 16)
                    .lineLimit(3)
            }

            if let summary = editor.project.enhancementSummary {
                Text(summary)
                    .font(.custom("AvenirNext-Medium", size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 16)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MediaLibraryKind.allCases) { kind in
                        Button {
                            editor.libraryKind = kind
                        } label: {
                            Label(kind.title, systemImage: kind.systemImage)
                                .font(.custom("AvenirNext-DemiBold", size: 12))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    editor.libraryKind == kind
                                    ? Color(red: 0.15, green: 0.9, blue: 0.72)
                                    : Color.white.opacity(0.08),
                                    in: Capsule()
                                )
                                .foregroundStyle(editor.libraryKind == kind ? .black : .white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(editor.libraries.items(for: editor.libraryKind)) { item in
                        LibraryTile(item: item, kind: editor.libraryKind) {
                            editor.addLibraryItem(item, kind: editor.libraryKind)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            if !editor.project.soundEffects.isEmpty && editor.libraryKind == .sfx {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Timeline SFX (\(editor.project.soundEffects.count))")
                        .font(.custom("AvenirNext-DemiBold", size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                    ForEach(editor.project.soundEffects.prefix(6)) { cue in
                        HStack {
                            Text(cue.assetId)
                                .font(.custom("AvenirNext-Medium", size: 12))
                                .foregroundStyle(.white)
                            Spacer()
                            Text(String(format: "%.1fs", cue.startTime))
                                .font(.custom("AvenirNext-Medium", size: 11))
                                .foregroundStyle(.white.opacity(0.4))
                            Button {
                                editor.previewSFX(cue)
                            } label: {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(red: 0.4, green: 0.95, blue: 0.8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
        .padding(.top, 8)
        .task {
            await editor.enhancer.checkHealth()
        }
    }

    private var enhanceButton: some View {
        Button {
            Task { await editor.enhanceWithCursorSDK() }
        } label: {
            HStack(spacing: 6) {
                if editor.isEnhancing {
                    ProgressView().controlSize(.small).tint(.black)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(editor.isEnhancing ? "Placing…" : "AI Place")
            }
            .font(.custom("AvenirNext-DemiBold", size: 12))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(red: 1.0, green: 0.92, blue: 0.35), in: Capsule())
            .foregroundStyle(.black)
        }
        .buttonStyle(.plain)
        .disabled(editor.isEnhancing || editor.project.captions.isEmpty)
    }
}

struct LibraryTile: View {
    let item: MediaLibraryItem
    let kind: MediaLibraryKind
    var onAdd: () -> Void

    @EnvironmentObject private var editor: EditorViewModel

    var body: some View {
        Button(action: onAdd) {
            VStack(spacing: 6) {
                preview
                    .frame(height: 72)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                Text(item.name)
                    .font(.custom("AvenirNext-Medium", size: 11))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)

                Text(metaLabel)
                    .font(.custom("AvenirNext-Medium", size: 9))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private var metaLabel: String {
        switch kind {
        case .sfx:
            return String(format: "%.2fs", item.playLength)
        case .gifs:
            return String(format: "%.2fs · %dx%d", item.playLength, Int(item.pixelSize.width), Int(item.pixelSize.height))
        case .pngs:
            return String(format: "%dx%d", Int(item.pixelSize.width), Int(item.pixelSize.height))
        case .textStyles:
            return String(format: "%.1fs hold", item.playLength)
        case .fonts:
            return (item.scripts ?? []).prefix(2).joined(separator: " · ")
        case .effects:
            return item.animation ?? item.id
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch kind {
        case .textStyles:
            Text(item.previewText ?? item.name)
                .font(.custom(item.fontName ?? "AvenirNext-Bold", size: 13))
                .foregroundStyle(Color(hex: item.textColor ?? "#FFFFFF") ?? .white)
                .shadow(radius: (item.shadowRadius ?? 0) > 0 ? 4 : 0)
                .padding(6)
                .multilineTextAlignment(.center)
        case .fonts:
            Text(item.previewText ?? "Aa")
                .font(.custom(item.fontName ?? "AvenirNext-Bold", size: 18))
                .foregroundStyle(.white)
                .padding(6)
        case .effects:
            VStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color(red: 1.0, green: 0.92, blue: 0.35))
                Text(item.animation ?? item.id)
                    .font(.custom("AvenirNext-Medium", size: 10))
                    .foregroundStyle(.white.opacity(0.7))
            }
        case .gifs, .pngs:
            if let file = item.file,
               let url = editor.libraries.fileURL(kind: kind, fileName: file) {
                LibraryImage(url: url)
                    .padding(8)
            } else {
                Image(systemName: kind.systemImage)
                    .foregroundStyle(.white.opacity(0.4))
            }
        case .sfx:
            VStack(spacing: 4) {
                Image(systemName: "waveform")
                    .font(.system(size: 22))
                    .foregroundStyle(Color(red: 0.4, green: 0.95, blue: 0.8))
                Text(item.tags.prefix(2).joined(separator: " · "))
                    .font(.custom("AvenirNext-Medium", size: 9))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}
}

struct LibraryImage: View {
    let url: URL

    var body: some View {
        #if canImport(UIKit)
        if let ui = UIImage(contentsOfFile: url.path) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
        }
        #elseif canImport(AppKit)
        if let ns = NSImage(contentsOf: url) {
            Image(nsImage: ns)
                .resizable()
                .scaledToFit()
        }
        #endif
    }
}