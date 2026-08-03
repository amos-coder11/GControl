import AVFoundation
import Combine
import MediaPlayer
import QuartzCore
import SwiftUI

/// Reproducción global de notas de voz (sigue al salir del chat / app).
@MainActor
final class ChatVoicePlaybackCoordinator: ObservableObject {
    static let shared = ChatVoicePlaybackCoordinator()

    enum Rate: Float, CaseIterable, Equatable {
        case x1 = 1.0
        case x1_5 = 1.5
        case x2 = 2.0

        var label: String {
            switch self {
            case .x1: return "1X"
            case .x1_5: return "1.5X"
            case .x2: return "2X"
            }
        }

        var next: Rate {
            switch self {
            case .x1: return .x1_5
            case .x1_5: return .x2
            case .x2: return .x1
            }
        }
    }

    struct Session: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
        let duration: TimeInterval
        let threadId: UUID?
        let fileURL: URL
    }

    @Published private(set) var session: Session?
    @Published private(set) var isPlaying = false
    /// No @Published: se actualiza a ~30 Hz; las vistas usan TimelineView para leerlo.
    private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var rate: Rate = .x1

    var progress: Double {
        guard duration > 0.01 else { return 0 }
        return min(1, max(0, currentTime / duration))
    }

    var isActive: Bool { session != nil }

    private var audioPlayer: AVAudioPlayer?
    private var streamPlayer: AVPlayer?
    private var tick: AnyCancellable?
    private var endObserver: NSObjectProtocol?
    private var ownsTempFile = false
    private var remoteConfigured = false
    private var lastNowPlayingElapsedAt: CFTimeInterval = 0

    private init() {
        configureRemoteCommandsIfNeeded()
    }

    func isPlayingItem(id: String) -> Bool {
        session?.id == id && isPlaying
    }

    func isActiveItem(id: String) -> Bool {
        session?.id == id
    }

    func progress(for id: String) -> Double {
        guard session?.id == id else { return 0 }
        return progress
    }

    func currentTime(for id: String) -> TimeInterval {
        guard session?.id == id else { return 0 }
        return currentTime
    }

    /// Inicia o pausa la misma nota; si es otra, la reemplaza.
    func toggle(
        id: String,
        title: String,
        subtitle: String,
        threadId: UUID?,
        data: Data,
        fileExtension: String,
        knownDuration: TimeInterval
    ) {
        if session?.id == id {
            togglePlayPause()
            return
        }
        playNew(
            id: id,
            title: title,
            subtitle: subtitle,
            threadId: threadId,
            data: data,
            fileExtension: fileExtension,
            knownDuration: knownDuration
        )
    }

    func togglePlayPause() {
        if let audioPlayer {
            if audioPlayer.isPlaying {
                audioPlayer.pause()
                isPlaying = false
                stopTick()
            } else {
                activateAudioSession()
                applyRate()
                audioPlayer.play()
                isPlaying = true
                startTick()
            }
            updateNowPlaying()
            return
        }
        if let streamPlayer {
            if isPlaying {
                streamPlayer.pause()
                isPlaying = false
                stopTick()
            } else {
                activateAudioSession()
                streamPlayer.play()
                streamPlayer.rate = rate.rawValue
                isPlaying = true
                startTick()
            }
            updateNowPlaying()
        }
    }

    func cycleRate() {
        rate = rate.next
        applyRate()
        updateNowPlaying()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func seek(toFraction fraction: Double) {
        guard duration > 0 else { return }
        let t = min(duration, max(0, fraction * duration))
        currentTime = t
        if let audioPlayer {
            audioPlayer.currentTime = t
            if !audioPlayer.isPlaying {
                activateAudioSession()
                applyRate()
                audioPlayer.play()
                isPlaying = true
                startTick()
            }
        } else if let streamPlayer {
            let cm = CMTime(seconds: t, preferredTimescale: 600)
            streamPlayer.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
            if !isPlaying {
                activateAudioSession()
                applyRate()
                streamPlayer.play()
                isPlaying = true
                startTick()
            }
        }
        updateNowPlaying()
    }

    /// Cierra el contenedor y detiene el audio.
    func dismiss() {
        tearDown(removeTemp: true)
    }

    // MARK: - Private

    private func playNew(
        id: String,
        title: String,
        subtitle: String,
        threadId: UUID?,
        data: Data,
        fileExtension: String,
        knownDuration: TimeInterval
    ) {
        tearDown(removeTemp: true)

        let ext = fileExtension.isEmpty ? "m4a" : fileExtension.lowercased()
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-global-\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: temp, options: .atomic)
            ownsTempFile = true
            activateAudioSession()

            let started: Bool
            let dur: TimeInterval
            if Self.prefersAudioPlayer(ext),
               let p = try? AVAudioPlayer(contentsOf: temp) {
                p.enableRate = true
                p.prepareToPlay()
                dur = max(p.duration, knownDuration, 0.35)
                p.delegate = PlaybackEndBridge.shared
                PlaybackEndBridge.shared.onFinish = { [weak self] in
                    Task { @MainActor in self?.dismiss() }
                }
                audioPlayer = p
                applyRate()
                started = p.play()
            } else {
                let item = AVPlayerItem(url: temp)
                let av = AVPlayer(playerItem: item)
                streamPlayer = av
                dur = max(knownDuration, 0.35)
                endObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: item,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.dismiss() }
                }
                av.play()
                // AVPlayer resetea rate al play(); aplicar velocidad después.
                av.rate = rate.rawValue
                started = true
                Task { await self.loadStreamDuration(from: temp, known: knownDuration) }
            }

            guard started else {
                dismiss()
                return
            }

            session = Session(
                id: id,
                title: title,
                subtitle: subtitle,
                duration: dur,
                threadId: threadId,
                fileURL: temp
            )
            duration = dur
            currentTime = 0
            isPlaying = true
            startTick()
            updateNowPlaying()
        } catch {
            try? FileManager.default.removeItem(at: temp)
            ownsTempFile = false
            session = nil
            isPlaying = false
        }
    }

    private static func prefersAudioPlayer(_ ext: String) -> Bool {
        ["m4a", "mp4", "mp3", "aac", "wav", "caf"].contains(ext)
    }

    private func loadStreamDuration(from url: URL, known: TimeInterval) async {
        let asset = AVURLAsset(url: url)
        let seconds: Double
        if #available(iOS 16.0, *) {
            if let loaded = try? await asset.load(.duration) {
                seconds = CMTimeGetSeconds(loaded)
            } else {
                seconds = known
            }
        } else {
            seconds = CMTimeGetSeconds(asset.duration)
        }
        await MainActor.run {
            guard seconds.isFinite, seconds > 0.2 else { return }
            duration = seconds
            if let s = session {
                session = Session(
                    id: s.id,
                    title: s.title,
                    subtitle: s.subtitle,
                    duration: seconds,
                    threadId: s.threadId,
                    fileURL: s.fileURL
                )
            }
            updateNowPlaying()
        }
    }

    private func applyRate() {
        if let audioPlayer {
            audioPlayer.enableRate = true
            audioPlayer.rate = rate.rawValue
        }
        if let streamPlayer {
            streamPlayer.rate = isPlaying ? rate.rawValue : 0
        }
    }

    private func activateAudioSession() {
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playback, mode: .spokenAudio, options: [])
        try? audio.setActive(true)
    }

    private func startTick() {
        stopTick()
        tick = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.syncFromPlayer()
            }
    }

    private func stopTick() {
        tick?.cancel()
        tick = nil
    }

    private func syncFromPlayer() {
        if let audioPlayer {
            currentTime = audioPlayer.currentTime
            if duration < 0.5, audioPlayer.duration > 0.5 {
                duration = audioPlayer.duration
            }
            if !audioPlayer.isPlaying, isPlaying {
                if currentTime >= max(0, duration - 0.08) {
                    dismiss()
                } else {
                    isPlaying = false
                    stopTick()
                }
            }
        } else if let streamPlayer {
            let t = streamPlayer.currentTime().seconds
            if t.isFinite { currentTime = max(0, t) }
            if !isPlaying {
                stopTick()
            }
        }
        updateNowPlayingElapsed()
    }

    private func tearDown(removeTemp: Bool) {
        stopTick()
        audioPlayer?.stop()
        audioPlayer = nil
        streamPlayer?.pause()
        streamPlayer = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        PlaybackEndBridge.shared.onFinish = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        if removeTemp, let url = session?.fileURL, ownsTempFile {
            try? FileManager.default.removeItem(at: url)
        }
        ownsTempFile = false
        session = nil
        clearNowPlaying()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func configureRemoteCommandsIfNeeded() {
        guard !remoteConfigured else { return }
        remoteConfigured = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.stopCommand.isEnabled = true
        center.changePlaybackRateCommand.isEnabled = true
        center.changePlaybackRateCommand.supportedPlaybackRates = [1.0, 1.5, 2.0]

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, self.session != nil, !self.isPlaying else { return }
                self.togglePlayPause()
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.togglePlayPause()
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
            return .success
        }
        center.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            Task { @MainActor in
                guard let self else { return }
                if let match = Rate.allCases.first(where: { abs($0.rawValue - event.playbackRate) < 0.01 }) {
                    self.rate = match
                    self.applyRate()
                    self.updateNowPlaying()
                }
            }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let session else {
            clearNowPlaying()
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: session.title,
            MPMediaItemPropertyAlbumTitle: session.subtitle,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate.rawValue) : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(rate.rawValue),
        ]
    }

    private func updateNowPlayingElapsed() {
        // Throttle: escribir Now Playing a 30 Hz es caro y no aporta en la UI del sistema.
        let now = CACurrentMediaTime()
        guard now - lastNowPlayingElapsedAt >= 0.5 else { return }
        lastNowPlayingElapsedAt = now
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(rate.rawValue) : 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}

private final class PlaybackEndBridge: NSObject, AVAudioPlayerDelegate {
    static let shared = PlaybackEndBridge()
    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }
}
