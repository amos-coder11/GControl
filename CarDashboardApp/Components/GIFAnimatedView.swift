import ImageIO
import SwiftUI
import UIKit

/// Reproduce un GIF del bundle con `UIImageView` (SwiftUI `Image` no anima GIF del catálogo).
struct GIFAnimatedView: UIViewRepresentable {
    var resourceName: String = "AIAssistantOrb"
    var bundle: Bundle = .main

    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.clipsToBounds = true
        v.backgroundColor = .clear
        load(into: v)
        return v
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        load(into: uiView)
    }

    private func load(into imageView: UIImageView) {
        guard let url = bundle.url(forResource: resourceName, withExtension: "gif"),
              let data = try? Data(contentsOf: url)
        else {
            imageView.image = nil
            imageView.stopAnimating()
            return
        }
        if let animated = Self.animatedUIImage(from: data) {
            imageView.image = animated
            imageView.startAnimating()
        } else if let still = UIImage(data: data) {
            imageView.image = still
            imageView.stopAnimating()
        } else {
            imageView.image = nil
        }
    }

    private static func animatedUIImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        if count == 1 {
            guard let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            return UIImage(cgImage: cg)
        }
        var images: [UIImage] = []
        var duration: TimeInterval = 0
        for i in 0 ..< count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]
            let gifDict = props?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            let delay =
                (gifDict?[kCGImagePropertyGIFUnclampedDelayTime as String] as? TimeInterval)
                ?? (gifDict?[kCGImagePropertyGIFDelayTime as String] as? TimeInterval)
                ?? 0.1
            duration += max(delay, 0.02)
            images.append(UIImage(cgImage: cg))
        }
        guard !images.isEmpty else { return nil }
        // `duration` en UIImage es el tiempo por fotograma, no el total del GIF.
        let perFrame = max(duration / Double(images.count), 0.02)
        return UIImage.animatedImage(with: images, duration: perFrame)
    }
}
