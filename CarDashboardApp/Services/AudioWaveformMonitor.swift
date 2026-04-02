import Accelerate
import AVFoundation
import Combine
import Foundation
import SwiftUI

// TODO: VERIFY — whether AVAudioEngine tap and WebRTC mic (stasel/WebRTC)
// can share the same AVAudioSession without conflict on iOS 16+.
// If conflict occurs, read amplitude from WebRTC audio track instead.

enum WaveformError: LocalizedError {
    case permissionDenied
    case audioEngineStartFailed(Error)
    case sessionSetupFailed(Error)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied."
        case let .audioEngineStartFailed(underlying):
            return "Audio engine failed: \(underlying.localizedDescription)"
        case let .sessionSetupFailed(underlying):
            return "Audio session failed: \(underlying.localizedDescription)"
        }
    }
}

/// Real-time microphone amplitude → rolling bar levels. Uses `ObservableObject` for iOS 16+.
/// (iOS 17+ `@Observable` could replace this type later without changing the audio pipeline.)
final class AudioWaveformMonitor: ObservableObject {
    /// Más barras → líneas más finas cuando el ancho se reparte (`fillsAvailableWidth`).
    static let barCount: Int = 72
    static let minDb: Float = -60.0
    static let maxDb: Float = 0.0

    private static let tapBufferSize: AVAudioFrameCount = 1024
    private static let smoothingPreviousWeight: Float = 0.3
    private static let smoothingNewWeight: Float = 0.7
    private static let minUpdateIntervalSeconds: CFTimeInterval = 0.033
    private static let idleTimerInterval: TimeInterval = 0.1
    private static let idleAmplitudeBase: Float = 0.08
    private static let idleAmplitudeSwing: Float = 0.06
    private static let idlePhaseIncrement: Double = 0.15
    private static let dbLogEpsilon: Float = Float.ulpOfOne
    private static let barAnimationDuration: Double = 0.08

    @Published private(set) var amplitudeLevels: [Float]
    @Published private(set) var isListening: Bool = false
    @Published var lastError: WaveformError?

    private let audioEngine = AVAudioEngine()
    private var usesInternalEngine: Bool = false
    /// When true, `ingestAudioBuffer` feeds the FIFO (shared session with speech recognition).
    private var externalFeedActive: Bool = false

    private var rollingBuffer: [Float]
    private var previousSmoothedLevel: Float = 0
    private var lastMainPublishTime: CFAbsoluteTime = 0
    private let processLock = NSLock()

    private var idleTimer: Timer?
    private var idleTimerTick: Double = 0

    init() {
        let count = Self.barCount
        let initial = Self.idleAmplitudeBase
        rollingBuffer = Array(repeating: initial, count: count)
        amplitudeLevels = rollingBuffer
        DispatchQueue.main.async { [weak self] in
            self?.startIdleTimer()
        }
    }

    deinit {
        idleTimer?.invalidate()
        if usesInternalEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
            if audioEngine.isRunning {
                audioEngine.stop()
            }
        }
    }

    // MARK: - Public API

    /// Own `AVAudioEngine` (e.g. `WaveformDemoView`). Do not use together with `beginExternalAudioFeed`.
    func startMonitoring() async {
        await MainActor.run { lastError = nil }

        let granted = await Self.requestRecordPermission()
        guard granted else {
            await MainActor.run { lastError = .permissionDenied }
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            await MainActor.run { lastError = .sessionSetupFailed(error) }
            return
        }

        stopIdleTimer()
        externalFeedActive = false
        resetProcessingStateLocked()

        await MainActor.run {
            self.isListening = true
            self.publishLevelsOnMain(self.rollingBuffer, animated: false)
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: Self.tapBufferSize, format: format) { [weak self] buffer, _ in
            self?.processAudioBufferForWaveform(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
            usesInternalEngine = true
        } catch {
            await MainActor.run {
                self.lastError = .audioEngineStartFailed(error)
                self.isListening = false
            }
            inputNode.removeTap(onBus: 0)
            startIdleTimer()
        }
    }

    func stopMonitoring() {
        if usesInternalEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
            if audioEngine.isRunning {
                audioEngine.stop()
            }
            usesInternalEngine = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        externalFeedActive = false
        resetProcessingStateLocked()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isListening = false
            self.applyIdleLevelsToPublished(animated: false)
        }
        startIdleTimer()
    }

    /// Call before `LiveSpeechTranscriber.startLiveTranscription()` (same session, no second engine).
    func beginExternalAudioFeed() {
        stopIdleTimer()
        externalFeedActive = true
        resetProcessingStateLocked()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isListening = true
            self.lastError = nil
            self.publishLevelsOnMain(self.rollingBuffer, animated: false)
        }
    }

    /// Call after `LiveSpeechTranscriber.stopLiveTranscription()`.
    func endExternalAudioFeed() {
        externalFeedActive = false
        resetProcessingStateLocked()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isListening = false
            self.applyIdleLevelsToPublished(animated: false)
        }
        startIdleTimer()
    }

    /// Invoked from `LiveSpeechTranscriber` audio tap (background thread).
    func ingestAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard externalFeedActive else { return }
        processAudioBufferForWaveform(buffer)
    }

    // MARK: - Audio processing (may run off main)

    private func processAudioBufferForWaveform(_ buffer: AVAudioPCMBuffer) {
        guard let rms = Self.computeRms(from: buffer) else { return }

        let db = 20 * log10(max(rms, Self.dbLogEpsilon))
        let range = Self.maxDb - Self.minDb
        let normalized = max(0, min(1, (db - Self.minDb) / range))

        processLock.lock()
        previousSmoothedLevel =
            previousSmoothedLevel * Self.smoothingPreviousWeight
            + normalized * Self.smoothingNewWeight
        let smoothed = previousSmoothedLevel
        if !rollingBuffer.isEmpty {
            rollingBuffer.removeFirst()
        }
        rollingBuffer.append(smoothed)
        let snapshot = rollingBuffer
        let now = CFAbsoluteTimeGetCurrent()
        let shouldPublish = (now - lastMainPublishTime) >= Self.minUpdateIntervalSeconds
        if shouldPublish {
            lastMainPublishTime = now
        }
        processLock.unlock()

        guard shouldPublish else { return }
        publishLevelsOnMain(snapshot, animated: true)
    }

    private static func computeRms(from buffer: AVAudioPCMBuffer) -> Float? {
        let n = Int(buffer.frameLength)
        guard n > 0 else { return nil }
        if let ch = buffer.floatChannelData?[0] {
            var rms: Float = 0
            vDSP_rmsqv(ch, 1, &rms, vDSP_Length(n))
            return rms
        }
        if let ch = buffer.int16ChannelData?[0] {
            var sum: Float = 0
            for i in 0 ..< n {
                let s = Float(ch[i]) / 32_768
                sum += s * s
            }
            return sqrt(sum / Float(n))
        }
        return nil
    }

    private static func requestRecordPermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        }
        await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { ok in
                cont.resume(returning: ok)
            }
        }
    }

    private func resetProcessingStateLocked() {
        processLock.lock()
        previousSmoothedLevel = 0
        lastMainPublishTime = 0
        rollingBuffer = Array(repeating: Self.idleAmplitudeBase, count: Self.barCount)
        processLock.unlock()
    }

    private func publishLevelsOnMain(_ levels: [Float], animated: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if animated {
                withAnimation(.easeOut(duration: Self.barAnimationDuration)) {
                    self.amplitudeLevels = levels
                }
            } else {
                self.amplitudeLevels = levels
            }
        }
    }

    private func applyIdleLevelsToPublished(animated: Bool) {
        let count = Self.barCount
        let tick = idleTimerTick
        let idleLevels: [Float] = (0 ..< count).map { i in
            let phase = Double(i) / Double(count) * 2 * Double.pi + tick
            return Self.idleAmplitudeBase + Self.idleAmplitudeSwing * Float(sin(phase))
        }
        publishLevelsOnMain(idleLevels, animated: animated)
    }

    // MARK: - Idle animation

    private func startIdleTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.idleTimer?.invalidate()
            self.idleTimer = Timer.scheduledTimer(withTimeInterval: Self.idleTimerInterval, repeats: true) { [weak self] timer in
                guard let self else {
                    timer.invalidate()
                    return
                }
                guard !self.isListening else { return }
                self.idleTimerTick += Self.idlePhaseIncrement
                let count = Self.barCount
                let tick = self.idleTimerTick
                let idleLevels: [Float] = (0 ..< count).map { i in
                    let phase = Double(i) / Double(count) * 2 * Double.pi + tick
                    return Self.idleAmplitudeBase + Self.idleAmplitudeSwing * Float(sin(phase))
                }
                self.amplitudeLevels = idleLevels
            }
            if let t = self.idleTimer {
                RunLoop.main.add(t, forMode: .common)
            }
        }
    }

    private func stopIdleTimer() {
        let op: () -> Void = { [weak self] in
            self?.idleTimer?.invalidate()
            self?.idleTimer = nil
        }
        if Thread.isMainThread {
            op()
        } else {
            DispatchQueue.main.async(execute: op)
        }
    }
}
