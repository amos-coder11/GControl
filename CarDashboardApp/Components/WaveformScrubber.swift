//
//  WaveformScrubber.swift
//  Scrubber de forma de onda (AudioScrubber / Balaji) para notas de voz.
//

import AVFoundation
import SwiftUI

struct WaveformScrubber: View {
    var config: Config = .init()
    var url: URL
    @Binding var progress: CGFloat
    var info: (AudioInfo) -> Void = { _ in }
    var onGestureActive: (Bool) -> Void = { _ in }

    @State private var samples: [Float] = []
    @State private var downsizedSamples: [Float] = []
    @State private var viewSize: CGSize = .zero
    @State private var lastProgress: CGFloat = 0
    @GestureState private var isActive = false

    var body: some View {
        ZStack {
            WaveformShape(samples: downsizedSamples, spacing: config.spacing, width: config.shapeWidth)
                .fill(config.inActiveTint)

            WaveformShape(samples: downsizedSamples, spacing: config.spacing, width: config.shapeWidth)
                .fill(config.activeTint)
                .mask {
                    Rectangle()
                        .scale(x: progress, anchor: .leading)
                }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .updating($isActive) { _, out, _ in
                    out = true
                }
                .onChanged { value in
                    let next = max(min((value.translation.width / max(viewSize.width, 1)) + lastProgress, 1), 0)
                    progress = next
                }
                .onEnded { _ in
                    lastProgress = progress
                }
        )
        .onChange(of: progress) { _, newValue in
            guard !isActive else { return }
            lastProgress = newValue
        }
        .onChange(of: isActive) { _, newValue in
            onGestureActive(newValue)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { newValue in
            if viewSize == .zero {
                lastProgress = progress
            }
            viewSize = newValue
            initializeAudioFile(newValue)
        }
    }

    struct Config {
        var spacing: Float = 2
        var shapeWidth: Float = 2
        var activeTint: Color = GrooChatTheme.telegramBlue
        var inActiveTint: Color = Color.black.opacity(0.22)
    }

    struct AudioInfo {
        var duration: TimeInterval = 0
    }
}

private struct WaveformShape: Shape {
    var samples: [Float]
    var spacing: Float = 2
    var width: Float = 2

    nonisolated func path(in rect: CGRect) -> Path {
        Path { path in
            var x: CGFloat = 0
            for sample in samples {
                let height = max(CGFloat(sample) * rect.height, 1)
                path.addRect(
                    CGRect(
                        origin: .init(x: x + CGFloat(width), y: -height / 2),
                        size: .init(width: CGFloat(width), height: height)
                    )
                )
                x += CGFloat(spacing + width)
            }
        }
        .offsetBy(dx: 0, dy: rect.height / 2)
    }
}

extension WaveformScrubber {
    private func initializeAudioFile(_ size: CGSize) {
        guard samples.isEmpty, size.width > 1 else { return }
        let fileURL = url
        let spacing = config.spacing
        let shapeWidth = config.shapeWidth

        Task.detached(priority: .high) {
            do {
                let audioFile = try AVAudioFile(forReading: fileURL)
                let audioInfo = Self.extractAudioInfo(audioFile)
                let samples = try Self.extractAudioSamples(audioFile)
                let downSampleCount = max(1, Int(Float(size.width) / (spacing + shapeWidth)))
                let downSamples = Self.downSampleAudioSamples(samples, downSampleCount)
                await MainActor.run {
                    self.samples = samples
                    self.downsizedSamples = downSamples
                    self.info(audioInfo)
                }
            } catch {
                #if DEBUG
                print("WaveformScrubber: \(error.localizedDescription)")
                #endif
            }
        }
    }

    nonisolated private static func extractAudioSamples(_ file: AVAudioFile) throws -> [Float] {
        let format = file.processingFormat
        let frameCount = UInt32(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return []
        }
        try file.read(into: buffer)
        if let channel = buffer.floatChannelData {
            return Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))
        }
        return []
    }

    nonisolated private static func downSampleAudioSamples(_ samples: [Float], _ count: Int) -> [Float] {
        guard count > 0, !samples.isEmpty else { return [] }
        let chunk = max(1, samples.count / count)
        var downSamples: [Float] = []
        downSamples.reserveCapacity(count)
        for index in 0 ..< count {
            let start = index * chunk
            let end = min((index + 1) * chunk, samples.count)
            guard start < end else { break }
            downSamples.append(samples[start ..< end].max() ?? 0)
        }
        return downSamples
    }

    nonisolated private static func extractAudioInfo(_ file: AVAudioFile) -> AudioInfo {
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return .init(duration: 0) }
        let duration = TimeInterval(file.length) / sampleRate
        return .init(duration: duration)
    }
}
