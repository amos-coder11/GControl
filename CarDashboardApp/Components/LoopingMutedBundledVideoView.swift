import AVFoundation
import SwiftUI
import UIKit

/// Vídeo del bundle en bucle, sin sonido (p. ej. orbe IA).
struct LoopingMutedBundledVideoView: UIViewRepresentable {
    var resourceName: String
    var fileExtension: String = "mp4"
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> LoopingBundledVideoUIView {
        let v = LoopingBundledVideoUIView()
        v.videoGravity = videoGravity
        if let url = Bundle.main.url(forResource: resourceName, withExtension: fileExtension) {
            v.start(url: url)
        }
        return v
    }

    func updateUIView(_ uiView: LoopingBundledVideoUIView, context: Context) {
        uiView.videoGravity = videoGravity
    }

    static func dismantleUIView(_ uiView: LoopingBundledVideoUIView, coordinator: Void) {
        uiView.stop()
    }
}

final class LoopingBundledVideoUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    var videoGravity: AVLayerVideoGravity = .resizeAspectFill {
        didSet { playerLayer.videoGravity = videoGravity }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        clipsToBounds = true
        backgroundColor = .clear
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
        playerLayer.videoGravity = videoGravity
    }

    func start(url: URL) {
        stop()
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        looper = AVPlayerLooper(player: queue, templateItem: item)
        queuePlayer = queue
        playerLayer.videoGravity = videoGravity
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
