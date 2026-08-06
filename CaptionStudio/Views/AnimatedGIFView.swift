import SwiftUI
import ImageIO
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Plays a transparent animated GIF, optionally scrub-synced to video time.
struct AnimatedGIFView: View {
    let url: URL
    /// Absolute timeline seconds (video clock). When nil, loops with wall-clock animation.
    var time: TimeInterval? = nil
    /// Overlay start on the timeline (used with `time`).
    var startTime: TimeInterval = 0

    @State private var frames: AnimatedGIFFrames = .empty

    var body: some View {
        Group {
            if let time {
                frameImage(localTime: max(0, time - startTime))
            } else if frames.isAnimated {
                TimelineView(.animation(minimumInterval: minFrameInterval, paused: false)) { context in
                    let local = context.date.timeIntervalSinceReferenceDate
                    frameImage(localTime: local)
                }
            } else {
                frameImage(localTime: 0)
            }
        }
        .onAppear { reload() }
        .onChange(of: url) { _ in reload() }
    }

    private var minFrameInterval: TimeInterval {
        guard let minDelay = frames.delays.min(), minDelay > 0 else { return 1.0 / 15.0 }
        return max(1.0 / 30.0, minDelay)
    }

    @ViewBuilder
    private func frameImage(localTime: TimeInterval) -> some View {
        if let cg = frames.image(at: localTime) {
            #if canImport(UIKit)
            Image(uiImage: UIImage(cgImage: cg))
                .resizable()
                .scaledToFit()
            #elseif canImport(AppKit)
            Image(nsImage: nsImage(from: cg))
                .resizable()
                .scaledToFit()
            #endif
        } else {
            Color.clear
        }
    }

    private func reload() {
        frames = AnimatedGIFDecoder.load(url: url)
    }

    #if canImport(AppKit)
    private func nsImage(from cg: CGImage) -> NSImage {
        NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
    #endif
}
