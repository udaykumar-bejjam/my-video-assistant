import Foundation
import AVFoundation
import Accelerate

/// Loudness normalize for dialogue + relative SFX gain caps.
/// Prefer ITU-R BS.1770-4 style **integrated LUFS** (P1.14); fall back to peak if too short.
/// Keep LUFS math in sync with `enhancer-server/src/lufs.js`.
enum AudioNormalizeService {
    /// Sample-peak ceiling after LUFS gain (~−3 dBFS headroom).
    static let targetPeak: Float = 0.70
    /// Short-form / social dialogue target (YouTube-ish).
    static let targetLUFS: Float = -14
    static let maxGain: Float = 4.0
    static let minGain: Float = 0.25

    private static let absGateLUFS: Float = -70
    private static let relGateLU: Float = -10
    private static let blockSeconds: Double = 0.4
    private static let overlap: Double = 0.75

    struct Normalization {
        var dialogueGain: Float
        var measuredPeak: Float
        var measuredLUFS: Float?
        var targetLUFS: Float
        var sfxGainScale: Double
        /// `lufs` | `peak-fallback`
        var mode: String
    }

    struct TrackGain {
        var track: AVAssetTrack
        var volume: Float
        /// Optional duck windows on this track (usually dialogue).
        var duckWindows: [(start: TimeInterval, end: TimeInterval, amount: Float)] = []
    }

    struct LoudnessMeasurement {
        var peak: Float
        var lufs: Float?
        var sampleRate: Double
    }

    // MARK: - Analyze

    static func analyzeDialoguePeak(videoURL: URL) async throws -> Float {
        try await analyzeDialogueLoudness(videoURL: videoURL).peak
    }

    /// Peak + integrated LUFS for the first audio track.
    static func analyzeDialogueLoudness(videoURL: URL) async throws -> LoudnessMeasurement {
        let asset = AVURLAsset(url: videoURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            return LoudnessMeasurement(peak: targetPeak, lufs: targetLUFS, sampleRate: 48_000)
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
            return LoudnessMeasurement(peak: targetPeak, lufs: nil, sampleRate: 48_000)
        }

        var peak: Float = 0.0001
        var mono: [Float] = []
        mono.reserveCapacity(48000 * 30)
        var sampleRate: Double = 48_000

        while let sample = output.copyNextSampleBuffer() {
            if let format = CMSampleBufferGetFormatDescription(sample),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format) {
                sampleRate = asbd.pointee.mSampleRate > 0 ? asbd.pointee.mSampleRate : sampleRate
            }
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var data = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &data)
            var localPeak: Float = 0
            vDSP_maxmgv(data, 1, &localPeak, vDSP_Length(data.count))
            peak = max(peak, localPeak)

            // Downmix interleaved → mono mean for LUFS.
            let channels: Int = {
                guard let format = CMSampleBufferGetFormatDescription(sample),
                      let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)
                else { return 1 }
                return max(1, Int(asbd.pointee.mChannelsPerFrame))
            }()
            if channels <= 1 {
                mono.append(contentsOf: data)
            } else {
                let frames = data.count / channels
                for f in 0..<frames {
                    var sum: Float = 0
                    for c in 0..<channels { sum += data[f * channels + c] }
                    mono.append(sum / Float(channels))
                }
            }
            // Cap analysis buffer (~3 min @ 48k) for memory.
            if mono.count > Int(sampleRate * 180) { break }
        }

        let lufs: Float?
        if mono.count >= Int(sampleRate * 0.35) {
            lufs = integratedLUFS(samples: mono, sampleRate: sampleRate)
        } else {
            lufs = nil
        }
        return LoudnessMeasurement(peak: peak, lufs: lufs, sampleRate: sampleRate)
    }

    static func normalization(
        measuredPeak: Float,
        brandSfxGain: Double
    ) -> Normalization {
        normalization(
            measurement: LoudnessMeasurement(peak: measuredPeak, lufs: nil, sampleRate: 48_000),
            brandSfxGain: brandSfxGain
        )
    }

    static func normalization(
        measurement: LoudnessMeasurement,
        brandSfxGain: Double,
        target: Float = targetLUFS
    ) -> Normalization {
        let peak = max(measurement.peak, 0.0001)
        if let lufs = measurement.lufs, lufs > -70, lufs.isFinite {
            var gain = pow(10, (target - lufs) / 20)
            gain = min(maxGain, max(minGain, gain))
            if peak * gain > targetPeak {
                gain = targetPeak / peak
                gain = min(maxGain, max(minGain, gain))
            }
            let sfxScale = min(1.0, brandSfxGain) * Double(min(1.0, targetPeak / max(peak * gain, 0.0001)))
            return Normalization(
                dialogueGain: gain,
                measuredPeak: peak,
                measuredLUFS: lufs,
                targetLUFS: target,
                sfxGainScale: max(0.15, min(1.2, sfxScale)),
                mode: "lufs"
            )
        }
        // Peak fallback (legacy).
        var gain = targetPeak / peak
        gain = min(maxGain, max(minGain, gain))
        let sfxScale = min(1.0, brandSfxGain) * Double(min(1.0, targetPeak / max(peak * gain, 0.0001)))
        return Normalization(
            dialogueGain: gain,
            measuredPeak: peak,
            measuredLUFS: nil,
            targetLUFS: target,
            sfxGainScale: max(0.15, min(1.2, sfxScale)),
            mode: "peak-fallback"
        )
    }

    // MARK: - LUFS (BS.1770-4)

    /// Integrated LUFS for mono float samples.
    static func integratedLUFS(samples: [Float], sampleRate: Double) -> Float {
        let sr = max(8_000, sampleRate)
        guard !samples.isEmpty else { return -120 }
        let weighted = kWeight(samples, sampleRate: sr)
        let blockSize = max(1, Int((sr * blockSeconds).rounded()))
        let hop = max(1, Int((Double(blockSize) * (1 - overlap)).rounded()))

        if weighted.count < blockSize {
            let ms = meanSquare(weighted)
            return lufsFromMS(ms)
        }

        var blockMS: [Float] = []
        var start = 0
        while start + blockSize <= weighted.count {
            blockMS.append(meanSquare(Array(weighted[start..<(start + blockSize)])))
            start += hop
        }
        guard !blockMS.isEmpty else { return lufsFromMS(meanSquare(weighted)) }

        let ungatedMS = blockMS.reduce(0, +) / Float(blockMS.count)
        let afterAbs = blockMS.filter { lufsFromMS($0) > absGateLUFS }
        guard !afterAbs.isEmpty else { return -70 }
        let absMean = afterAbs.reduce(0, +) / Float(afterAbs.count)
        let relativeThresh = lufsFromMS(absMean) - relGateLU
        let gated = afterAbs.filter { lufsFromMS($0) > relativeThresh }
        let use = gated.isEmpty ? afterAbs : gated
        let gatedMS = use.reduce(0, +) / Float(use.count)
        return lufsFromMS(gatedMS)
    }

    private static func lufsFromMS(_ ms: Float) -> Float {
        guard ms > 0 else { return -120 }
        return -0.691 + 10 * log10(ms)
    }

    private static func meanSquare(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        vDSP_svesq(samples, 1, &sum, vDSP_Length(samples.count))
        return sum / Float(samples.count)
    }

    private static func kWeight(_ samples: [Float], sampleRate: Double) -> [Float] {
        let filters = kWeightFilters(sampleRate: sampleRate)
        let stage1 = applyBiquad(samples, b: filters.pre.b, a: filters.pre.a)
        return applyBiquad(stage1, b: filters.rlb.b, a: filters.rlb.a)
    }

    private struct Biquad {
        var b: [Float]
        var a: [Float]
    }

    private static func kWeightFilters(sampleRate: Double) -> (pre: Biquad, rlb: Biquad) {
        if abs(sampleRate - 48_000) < 50 {
            return (
                pre: Biquad(
                    b: [1.53512485958697, -2.69169618940638, 1.19839281085285],
                    a: [1.0, -1.69065929318241, 0.73248077421585]
                ),
                rlb: Biquad(
                    b: [1.0, -2.0, 1.0],
                    a: [1.0, -1.99004745483398, 0.99007225036621]
                )
            )
        }
        if abs(sampleRate - 44_100) < 50 {
            return (
                pre: Biquad(
                    b: [1.5308412300503478, -2.6509799950757456, 1.1690790799215877],
                    a: [1.0, -1.6636551132567342, 0.7125954263059514]
                ),
                rlb: Biquad(
                    b: [1.0, -2.0, 1.0],
                    a: [1.0, -1.9891845679314284, 0.9892245165138008]
                )
            )
        }
        return kWeightFilters(sampleRate: 48_000)
    }

    private static func applyBiquad(_ samples: [Float], b: [Float], a: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: samples.count)
        var x1: Float = 0
        var x2: Float = 0
        var y1: Float = 0
        var y2: Float = 0
        for i in samples.indices {
            let x0 = samples[i]
            let y0 = b[0] * x0 + b[1] * x1 + b[2] * x2 - a[1] * y1 - a[2] * y2
            out[i] = y0
            x2 = x1
            x1 = x0
            y2 = y1
            y1 = y0
        }
        return out
    }

    // MARK: - Mix

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
