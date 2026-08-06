import Foundation
import AVFoundation
import Accelerate

/// Approximate loudness normalize for dialogue + relative SFX gain caps.
enum AudioNormalizeService {
    /// Target peak linear amplitude for dialogue (~ -3 dBFS peak ceiling with headroom).
    static let targetPeak: Float = 0.70
    static let maxGain: Float = 4.0
    static let minGain: Float = 0.25

    struct Normalization {
        var dialogueGain: Float
        var measuredPeak: Float
        var sfxGainScale: Double
    }

    struct TrackGain {
        var track: AVAssetTrack
        var volume: Float
        /// Optional duck windows on this track (usually dialogue).
        var duckWindows: [(start: TimeInterval, end: TimeInterval, amount: Float)] = []
    }

    static func analyzeDialoguePeak(videoURL: URL) async throws -> Float {
        let asset = AVURLAsset(url: videoURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            return targetPeak
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false
            ]
        )
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else {
            return targetPeak
        }

        var peak: Float = 0.0001
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var data = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &data)
            var localPeak: Float = 0
            vDSP_maxmgv(data, 1, &localPeak, vDSP_Length(data.count))
            peak = max(peak, localPeak)
        }
        return peak
    }

    static func normalization(
        measuredPeak: Float,
        brandSfxGain: Double
    ) -> Normalization {
        let peak = max(measuredPeak, 0.0001)
        var gain = targetPeak / peak
        gain = min(maxGain, max(minGain, gain))
        // Keep SFX under dialogue after dialogue gain is applied.
        let sfxScale = min(1.0, brandSfxGain) * Double(min(1.0, targetPeak / max(peak * gain, 0.0001)))
        return Normalization(
            dialogueGain: gain,
            measuredPeak: peak,
            sfxGainScale: max(0.15, min(1.2, sfxScale))
        )
    }

    /// Legacy helper — uniform SFX volume under dialogue.
    static func audioMix(
        for composition: AVMutableComposition,
        dialogueGain: Float
    ) -> AVMutableAudioMix? {
        let audioTracks = composition.tracks(withMediaType: .audio)
        guard let first = audioTracks.first else { return nil }
        var gains: [TrackGain] = [
            TrackGain(track: first, volume: dialogueGain)
        ]
        for track in audioTracks.dropFirst() {
            gains.append(TrackGain(track: track, volume: min(1.0, dialogueGain * 0.85)))
        }
        return audioMix(gains: gains)
    }

    /// Per-track volumes + optional dialogue duck windows around SFX.
    static func audioMix(gains: [TrackGain]) -> AVMutableAudioMix? {
        guard !gains.isEmpty else { return nil }
        var params: [AVMutableAudioMixInputParameters] = []
        for gain in gains {
            let p = AVMutableAudioMixInputParameters(track: gain.track)
            let base = max(0, min(1.5, gain.volume))
            p.setVolume(base, at: .zero)
            for window in gain.duckWindows {
                let ducked = max(0.05, base * (1 - min(0.85, window.amount)))
                let start = CMTime(seconds: max(0, window.start), preferredTimescale: 600)
                let end = CMTime(seconds: max(window.start + 0.05, window.end), preferredTimescale: 600)
                let fade: TimeInterval = 0.05
                let duckIn = CMTime(seconds: max(0, window.start - fade), preferredTimescale: 600)
                let duckOut = CMTime(seconds: window.end + fade, preferredTimescale: 600)
                let fadeIn = CMTimeRange(
                    start: duckIn,
                    duration: CMTimeMaximum(.zero, CMTimeSubtract(start, duckIn))
                )
                let fadeOut = CMTimeRange(
                    start: end,
                    duration: CMTimeMaximum(.zero, CMTimeSubtract(duckOut, end))
                )
                if fadeIn.duration.seconds > 0 {
                    p.setVolumeRamp(fromStartVolume: base, toEndVolume: ducked, timeRange: fadeIn)
                }
                p.setVolume(ducked, at: start)
                if fadeOut.duration.seconds > 0 {
                    p.setVolumeRamp(fromStartVolume: ducked, toEndVolume: base, timeRange: fadeOut)
                }
                p.setVolume(base, at: duckOut)
            }
            params.append(p)
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = params
        return mix
    }
}
