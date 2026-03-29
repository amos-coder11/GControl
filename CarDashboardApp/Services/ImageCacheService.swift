import UIKit

/// Caché L1 en memoria para imágenes ya decodificadas.
/// Complementa la caché L2 en disco de URLCache (300 MB).
final class ImageCacheService {
    static let shared = ImageCacheService()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        // ~300 imágenes downsampled en memoria (cada una ~300-500 KB tras downsampling)
        cache.countLimit = 300
        // ~150 MB máximo — suficiente para scroll fluido sin re-decodificar
        cache.totalCostLimit = 150 * 1024 * 1024

        // Liberar memoria cuando el sistema lo pida
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cache.removeAllObjects()
        }
    }

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: UIImage, forKey key: String) {
        // Costo basado en bytes reales del bitmap tras downsampling
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func remove(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    func clearAll() {
        cache.removeAllObjects()
    }
}
