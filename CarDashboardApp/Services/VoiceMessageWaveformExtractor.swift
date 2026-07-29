import AVFoundation
import CoreMedia
import Foundation

/// Genera barras de amplitud [0,1] a partir de audio en memoria o en disco (notas de voz en chat).
enum VoiceMessageWaveformExtractor {
    /// Duración en segundos; útil sin decodificar todo el archivo cuando solo hace falta el tiempo.
    static func durationSeconds(ofM4AData data: Data) -> TimeInterval? {
        durationSeconds(ofAudioData: data, fileExtension: "m4a")
    }

    /// Duración de cualquier audio en memoria (m4a, ogg, mp3…).
    static func durationSeconds(ofAudioData data: Data, fileExtension: String) -> TimeInterval? {
        let ext = normalizedExtension(fileExtension)
        if ext == "m4a" || ext == "mp4" {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("wf-dur-\(UUID().uuidString).\(ext)")
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                try data.write(to: url)
                let file = try AVAudioFile(forReading: url)
                let rate = file.fileFormat.sampleRate
                guard rate > 0 else { return nil }
                return TimeInterval(file.length) / rate
            } catch {}
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wf-dur-\(UUID().uuidString).\(ext)")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try data.write(to: url)
            let asset = AVURLAsset(url: url)
            let seconds = CMTimeGetSeconds(asset.duration)
            guard seconds.isFinite, seconds > 0 else { return nil }
            return seconds
        } catch {
            return nil
        }
    }

    static func waveformBars(fromM4AData data: Data, barCount: Int = 44) -> [CGFloat] {
        waveformBars(fromAudioData: data, fileExtension: "m4a", barCount: barCount)
    }

    /// Barras normalizadas según el audio real (m4a, ogg/opus, mp3, aac…).
    static func waveformBars(fromAudioData data: Data, fileExtension: String, barCount: Int = 44) -> [CGFloat] {
        let ext = normalizedExtension(fileExtension)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wf-\(UUID().uuidString).\(ext)")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try data.write(to: url)
            return try waveformBars(fromAudioURL: url, barCount: barCount)
        } catch {
            return placeholderBars(count: barCount)
        }
    }

    static func waveformBars(fromAudioURL url: URL, barCount: Int) throws -> [CGFloat] {
        let ext = url.pathExtension.lowercased()
        if ["m4a", "caf", "wav", "aiff", "aif"].contains(ext) {
            if let bars = try? waveformBarsViaAudioFile(url: url, barCount: barCount),
               looksLikeRealWaveform(bars) {
                return bars
            }
        }
        if let bars = try? waveformBarsViaAssetReader(url: url, barCount: barCount),
           looksLikeRealWaveform(bars) {
            return bars
        }
        if ext == "m4a" || ext == "mp4" {
            return try waveformBarsViaAudioFile(url: url, barCount: barCount)
        }
        return placeholderBars(count: barCount)
    }

    private static func waveformBarsViaAudioFile(url: URL, barCount: Int) throws -> [CGFloat] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let totalFrames = file.length
        guard totalFrames > 0, format.channelCount > 0 else {
            return placeholderBars(count: barCount)
        }

        let segments = max(1, barCount)
        let framesPerSegment = max(AVAudioFramePosition(1), totalFrames / AVAudioFramePosition(segments))

        file.framePosition = 0
        var peaks: [CGFloat] = []
        peaks.reserveCapacity(segments)

        while peaks.count < segments {
            let remaining = totalFrames - file.framePosition
            guard remaining > 0 else { break }
            let chunk = AVAudioFrameCount(
                min(AVAudioFramePosition(framesPerSegment), remaining)
            )
            guard chunk > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk)
            else { break }
            do {
                try file.read(into: buffer, frameCount: chunk)
            } catch {
                break
            }
            peaks.append(peakAmplitude(from: buffer, channelCount: Int(format.channelCount)))
        }

        while peaks.count < segments {
            peaks.append(0.02)
        }

        return normalizePeaks(peaks)
    }

    private static func waveformBarsViaAssetReader(url: URL, barCount: Int) throws -> [CGFloat] {
        let asset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        guard duration.isFinite, duration > 0.05 else {
            return placeholderBars(count: barCount)
        }

        guard let track = asset.tracks(withMediaType: .audio).first else {
            return placeholderBars(count: barCount)
        }

        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return placeholderBars(count: barCount) }
        reader.add(output)
        guard reader.startReading() else { return placeholderBars(count: barCount) }

        let segments = max(1, barCount)
        var peaks = Array(repeating: CGFloat(0), count: segments)

        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
            let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            let progress = min(1, max(0, time / duration))
            let index = min(segments - 1, Int(progress * Double(segments)))
            let peak = peakAmplitude(from: sampleBuffer)
            peaks[index] = max(peaks[index], peak)
        }

        return normalizePeaks(smoothPeaks(peaks))
    }

    private static func smoothPeaks(_ peaks: [CGFloat]) -> [CGFloat] {
        guard peaks.count > 2 else { return peaks }
        return peaks.indices.map { i in
            let left = peaks[max(0, i - 1)]
            let mid = peaks[i]
            let right = peaks[min(peaks.count - 1, i + 1)]
            return max(mid, (left + mid + right) / 3 * 0.94)
        }
    }

    private static func peakAmplitude(from sampleBuffer: CMSampleBuffer) -> CGFloat {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return 0 }
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )
        guard status == kCMBlockBufferNoErr, let dataPointer, length >= 2 else { return 0 }

        let sampleCount = length / MemoryLayout<Int16>.size
        guard sampleCount > 0 else { return 0 }

        var maxAbs: Float = 0
        dataPointer.withMemoryRebound(to: Int16.self, capacity: sampleCount) { ptr in
            for i in 0 ..< sampleCount {
                maxAbs = max(maxAbs, abs(Float(ptr[i]) / Float(Int16.max)))
            }
        }
        return CGFloat(maxAbs)
    }

    private static func peakAmplitude(from buffer: AVAudioPCMBuffer, channelCount: Int) -> CGFloat {
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var maxAbs: Float = 0
        if let floatData = buffer.floatChannelData {
            for ch in 0 ..< min(channelCount, Int(buffer.format.channelCount)) {
                let ptr = floatData[ch]
                for i in 0 ..< n {
                    maxAbs = max(maxAbs, abs(ptr[i]))
                }
            }
        } else if let int16 = buffer.int16ChannelData {
            for ch in 0 ..< min(channelCount, Int(buffer.format.channelCount)) {
                let ptr = int16[ch]
                for i in 0 ..< n {
                    let s = Float(ptr[i]) / Float(Int16.max)
                    maxAbs = max(maxAbs, abs(s))
                }
            }
        }
        return CGFloat(maxAbs)
    }

    private static func normalizePeaks(_ peaks: [CGFloat]) -> [CGFloat] {
        let maxPeak = peaks.max().map { max($0, 0.000_1) } ?? 1
        return peaks.map { p in
            let n = CGFloat(p / maxPeak)
            return max(0.08, min(1, 0.1 + n * 0.9))
        }
    }

    private static func looksLikeRealWaveform(_ bars: [CGFloat]) -> Bool {
        guard bars.count >= 4 else { return false }
        let minV = bars.min() ?? 0
        let maxV = bars.max() ?? 0
        return (maxV - minV) > 0.04
    }

    private static func normalizedExtension(_ fileExtension: String) -> String {
        let ext = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ext.isEmpty { return "m4a" }
        if ext == "opus" { return "ogg" }
        return ext
    }

    private static func placeholderBars(count: Int) -> [CGFloat] {
        (0 ..< count).map { i in
            let t = CGFloat(i) / CGFloat(max(1, count - 1))
            return 0.2 + 0.35 * (0.5 + 0.5 * sin(t * .pi * 3))
        }
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds.rounded(.down))
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }
}
