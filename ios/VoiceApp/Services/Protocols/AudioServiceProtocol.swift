import Foundation

/// Audio session lifecycle and microphone permission.
protocol AudioServiceProtocol: AnyObject {
    /// Configures `AVAudioSession` for two-way voice.
    func setup() throws

    /// Requests microphone permission; returns `true` if granted.
    func requestPermission() async -> Bool

    /// Deactivates the audio session.
    func tearDown()

    /// Called when an audio interruption begins (e.g. phone call).
    var onInterruptionBegan: (() -> Void)? { get set }

    /// Called when interruption ends; `shouldResume` indicates system hint to resume.
    var onInterruptionEnded: ((_ shouldResume: Bool) -> Void)? { get set }
}
