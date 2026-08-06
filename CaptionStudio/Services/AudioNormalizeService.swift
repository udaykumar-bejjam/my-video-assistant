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

    static func audioMix(
        for composition: AVMutableComposition,
        dialogueGain: Float
    ) -> AVMutableAudioMix? {
        let audioTracks = composition.tracks(withMediaType: .audio)
        guard let first = audioTracks.first else { return nil }
        var all: [AVMutableAudioMixInputParameters] = []
        let dialogue = AVMutableAudioMixInputParameters(track: first)
        dialogue.setVolume(dialogueGain, at: .zero)
        all.append(dialogue)
        for track in audioTracks.dropFirst() {
            let p = AVMutableAudioMixInputParameters(track: track)
            p.setVolume(min(1.0, dialogueGain * 0.85), at: .zero)
            all.append(p)
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = all
        return mix
    }
}
