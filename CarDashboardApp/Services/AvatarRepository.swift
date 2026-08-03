import Foundation
import UIKit

/// Caché y descarga de avatares con dedupe y concurrencia limitada.
actor AvatarRepository {
    static let shared = AvatarRepository()

    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private var activeDownloads = 0
    private let maxConcurrent = 4
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private(set) var cacheHits = 0
    private(set) var downloads = 0

    /// Clave estable: prioriza id de contacto/conversación sobre URL firmada.
    nonisolated static func cacheKey(stableId: String?, url: URL) -> String {
        if let stableId, !stableId.isEmpty {
            return "avatar:\(stableId)"
        }
        // Quita query de firma si existe (URL temporales).
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.query = nil
        comps?.fragment = nil
        return comps?.string ?? url.absoluteString
    }

    func image(stableId: String?, url: URL, accessToken: String?) async -> UIImage? {
        let key = Self.cacheKey(stableId: stableId, url: url)
        if let cached = ImageCacheService.shared.image(forKey: key)
            ?? ImageCacheService.shared.image(forKey: url.absoluteString) {
            cacheHits += 1
            ChatPerfLog.avatar("cache hit")
            return cached
        }

        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> {
            await self.withDownloadSlot {
                let img = await CrmContactPhotoLoader.load(url: url, accessToken: accessToken)
                if let img {
                    ImageCacheService.shared.store(img, forKey: key)
                    ImageCacheService.shared.store(img, forKey: url.absoluteString)
                    await self.bumpDownload()
                    ChatPerfLog.avatar("downloaded")
                }
                return img
            }
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    private func bumpDownload() {
        downloads += 1
    }

    private func withDownloadSlot<T: Sendable>(_ body: @Sendable () async -> T) async -> T {
        while activeDownloads >= maxConcurrent {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                waiters.append(cont)
            }
        }
        activeDownloads += 1
        defer {
            activeDownloads -= 1
            if !waiters.isEmpty {
                let next = waiters.removeFirst()
                next.resume()
            }
        }
        return await body()
    }
}
