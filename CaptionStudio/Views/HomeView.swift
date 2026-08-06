import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import PhotosUI

struct HomeView: View {
    @EnvironmentObject private var editor: EditorViewModel
    @State private var showImporter = false
    @State private var isLoadingSample = false
    @State private var appear = false
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            AtmosphereBackground()

            VStack(spacing: 0) {
                Spacer(minLength: 40)

                VStack(spacing: 18) {
                    Text("CaptionStudio")
                        .font(.custom("AvenirNext-Heavy", size: 44))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.95, blue: 0.85),
                                    Color(red: 0.55, green: 0.95, blue: 0.82)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 16)

                    Text("AI captions & overlays for short video.")
                        .font(.custom("AvenirNext-Medium", size: 17))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 12)

                    HStack(spacing: 14) {
                        #if os(iOS)
                        PhotosPicker(selection: $photoItem, matching: .videos) {
                            Label("Import Video", systemImage: "film.stack")
                                .font(.custom("AvenirNext-DemiBold", size: 16))
                                .padding(.horizontal, 22)
                                .padding(.vertical, 14)
                                .background(Color(red: 0.15, green: 0.9, blue: 0.72), in: Capsule())
                                .foregroundStyle(.black)
                        }
                        .buttonStyle(.plain)
                        #else
                        Button {
                            showImporter = true
                        } label: {
                            Label("Import Video", systemImage: "film.stack")
                                .font(.custom("AvenirNext-DemiBold", size: 16))
                                .padding(.horizontal, 22)
                                .padding(.vertical, 14)
                                .background(Color(red: 0.15, green: 0.9, blue: 0.72), in: Capsule())
                                .foregroundStyle(.black)
                        }
                        .buttonStyle(.plain)
                        #endif

                        Button {
                            Task { await loadDemoReel() }
                        } label: {
                            Label(isLoadingSample ? "Preparing…" : "Try Demo", systemImage: "play.circle.fill")
                                .font(.custom("AvenirNext-DemiBold", size: 16))
                                .padding(.horizontal, 22)
                                .padding(.vertical, 14)
                                .background(.white.opacity(0.12), in: Capsule())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoadingSample)
                    }
                    .padding(.top, 10)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 10)

                    PackPickerView(compact: true)
                        .padding(.top, 18)
                        .opacity(appear ? 1 : 0)
                }
                .padding(.horizontal, 28)

                Spacer()

                // Full-bleed atmospheric hero strip (not a card)
                HeroReelStrip()
                    .frame(height: 220)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 24)
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await editor.loadVideo(url: url) }
            case .failure(let error):
                editor.errorMessage = error.localizedDescription
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) {
                appear = true
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                do {
                    if let movie = try await item.loadTransferable(type: MovieFile.self) {
                        await editor.loadVideo(url: movie.url)
                    } else {
                        showImporter = true
                    }
                } catch {
                    showImporter = true
                    editor.errorMessage = error.localizedDescription
                }
                photoItem = nil
            }
        }
    }

    /// Builds a short silent demo clip so the editor is usable without importing.
    private func loadDemoReel() async {
        isLoadingSample = true
        defer { isLoadingSample = false }
        do {
            let url = try await DemoVideoFactory.makeDemoVideo()
            await editor.loadVideo(url: url)
            await editor.generateCaptions()
        } catch {
            editor.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Atmosphere

struct AtmosphereBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.08, blue: 0.1),
                    Color(red: 0.02, green: 0.12, blue: 0.14),
                    Color(red: 0.04, green: 0.06, blue: 0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(red: 0.1, green: 0.85, blue: 0.7).opacity(0.18))
                .frame(width: 420, height: 420)
                .blur(radius: 90)
                .offset(x: -120, y: -180)

            Circle()
                .fill(Color(red: 1.0, green: 0.75, blue: 0.35).opacity(0.12))
                .frame(width: 360, height: 360)
                .blur(radius: 80)
                .offset(x: 140, y: 220)
        }
    }
}

struct HeroReelStrip: View {
    @State private var phase: CGFloat = 0

    private let frames: [(String, Color)] = [
        ("Auto captions", Color(red: 0.12, green: 0.55, blue: 0.48)),
        ("Karaoke glow", Color(red: 0.18, green: 0.22, blue: 0.28)),
        ("Emoji pops", Color(red: 0.45, green: 0.32, blue: 0.12)),
        ("Export MP4", Color(red: 0.1, green: 0.35, blue: 0.4))
    ]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Array(frames.enumerated()), id: \.offset) { index, frame in
                    ZStack(alignment: .bottomLeading) {
                        frame.1
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        Text(frame.0)
                            .font(.custom("AvenirNext-Bold", size: 18))
                            .foregroundStyle(.white)
                            .padding(20)
                            .offset(y: sin(phase + Double(index)) * 6)
                    }
                    .frame(width: geo.size.width / 2.2, height: geo.size.height)
                }
            }
            .offset(x: -phase * 12)
            .frame(width: geo.size.width, alignment: .leading)
            .clipped()
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }
}

// MARK: - Demo video (solid color + tone)

enum DemoVideoFactory {
    static func makeDemoVideo() async throws -> URL {
        let size = CGSize(width: 720, height: 1280)
        let fps: Int32 = 30
        let durationSeconds = 8.0
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionStudio-Demo-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: url)

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            throw ExportError.exportFailed("Could not create demo writer.")
        }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameCount = Int(durationSeconds * Double(fps))
        var frame = 0

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            input.requestMediaDataWhenReady(on: DispatchQueue(label: "demo.video")) {
                while input.isReadyForMoreMediaData && frame < frameCount {
                    let time = CMTime(value: CMTimeValue(frame), timescale: fps)
                    if let buffer = makePixelBuffer(size: size, frame: frame, total: frameCount) {
                        adaptor.append(buffer, withPresentationTime: time)
                    }
                    frame += 1
                }
                if frame >= frameCount {
                    input.markAsFinished()
                    writer.finishWriting {
                        if writer.status == .completed {
                            continuation.resume()
                        } else {
                            continuation.resume(
                                throwing: writer.error ?? ExportError.exportFailed("Demo video failed.")
                            )
                        }
                    }
                }
            }
        }

        return url
    }

    private static func makePixelBuffer(size: CGSize, frame: Int, total: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32ARGB,
            nil,
            &buffer
        )
        guard let buffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return buffer }

        let t = CGFloat(frame) / CGFloat(max(total - 1, 1))
        let color = CGColor(
            red: 0.05 + 0.15 * t,
            green: 0.25 + 0.35 * (1 - abs(t - 0.5) * 2),
            blue: 0.28 + 0.2 * t,
            alpha: 1
        )
        ctx.setFillColor(color)
        ctx.fill(CGRect(origin: .zero, size: size))

        // Soft vignette circle for visual interest
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.06))
        let r = size.width * (0.25 + 0.1 * sin(t * .pi * 2))
        ctx.fillEllipse(in: CGRect(
            x: size.width * 0.5 - r,
            y: size.height * 0.4 - r,
            width: r * 2,
            height: r * 2
        ))

        return buffer
    }
}

/// Transferable wrapper for PhotosPicker video files.
struct MovieFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("photo-\(UUID().uuidString)-\(received.file.lastPathComponent)")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return MovieFile(url: dest)
        }
    }
}
