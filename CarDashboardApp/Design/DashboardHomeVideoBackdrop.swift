import AVFoundation
import SwiftUI
import UIKit

/// Vídeo de fondo de Inicio: `Resources/cab6b0cf98f7935fc0365a8ee1191735.mp4`, bucle y sin audio.
struct DashboardHomeBackdropImage: View {
    var body: some View {
        ZStack {
            if let url = Bundle.main.url(
                forResource: "cab6b0cf98f7935fc0365a8ee1191735",
                withExtension: "mp4"
            ) {
                LoopingMutedVideoFillView(url: url)
            } else {
                Color.black
            }
            Color.black.opacity(0.5)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .ignoresSafeArea()
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct LoopingMutedVideoFillView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> VideoFillUIView {
        let v = VideoFillUIView()
        v.start(url: url)
        return v
    }

    func updateUIView(_ uiView: VideoFillUIView, context: Context) {}

    static func dismantleUIView(_ uiView: VideoFillUIView, coordinator: Void) {
        uiView.stop()
    }
}

private final class VideoFillUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    func start(url: URL) {
        stop()
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        looper = AVPlayerLooper(player: queue, templateItem: item)
        queuePlayer = queue
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.player = queue
        queue.isMuted = true
        queue.volume = 0
        queue.play()
    }

    func stop() {
        queuePlayer?.pause()
        looper?.disableLooping()
        looper = nil
        queuePlayer = nil
        playerLayer.player = nil
    }
}
