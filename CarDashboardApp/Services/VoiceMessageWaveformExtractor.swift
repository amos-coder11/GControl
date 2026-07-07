import AVFoundation
import Foundation

/// Genera barras de amplitud [0,1] a partir de un .m4a en memoria o en disco (para notas de voz en chat).
enum VoiceMessageWaveformExtractor {
    /// Duración en segundos; útil sin decodificar todo el archivo cuando solo hace falta el tiempo.
    static func durationSeconds(ofM4AData data: Data) -> TimeInterval? {
        durationSeconds(ofAudioData: data, fileExtension: "m4a")
    }

    /// Duración de cualquier audio en memoria (m4a, ogg, mp3…).
    static func durationSeconds(ofAudioData data: Data, fileExtension: String) -> TimeInterval? {
        if fileExtension == "m4a" || fileExtension == "mp4" {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("wf-dur-\(UUID().uuidString).m4a")
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                try data.write(to: url)
                let file = try AVAudioFile(forReading: url)
                let rate = file.fileFormat.sampleRate
                guard rate > 0 else { return nil }
                return TimeInterval(file.length) / rate
            } catch {}
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wf-dur-\(UUID().uuidString).\(fileExtension)")
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

    /// Barras normalizadas (mínimo ~0.12 para silencios) según pico por segmento del audio.
    static func waveformBars(fromM4AData data: Data, barCount: Int = 44) -> [CGFloat] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wf-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try data.write(to: url)
            return try waveformBars(fromAudioURL: url, barCount: barCount)
        } catch {
            return placeholderBars(count: barCount)
        }
    }

    static func waveformBars(fromAudioURL url: URL, barCount: Int) throws -> [CGFloat] {
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

        let maxPeak = peaks.max().map { max($0, 0.000_1) } ?? 1
        return peaks.map { p in
            let n = CGFloat(p / maxPeak)
            return max(0.1, min(1, 0.12 + n * 0.88))
        }
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
