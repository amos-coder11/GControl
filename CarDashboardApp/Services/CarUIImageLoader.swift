import Foundation
import Supabase
import UIKit

// MARK: - Cargador de imágenes de vehículos optimizado para velocidad

/// Carga imágenes con: caché L1 (memoria) + L2 (disco URLCache), deduplicación,
/// downsampling al tamaño de pantalla, prefetch de vecinos, timeouts agresivos,
/// y conexión HTTP/2 multiplexada.
enum CarUIImageLoader {

    // MARK: - Configuración

    /// Timeout global por imagen (incluye reintentos)
    private static let imageTimeoutSeconds: TimeInterval = 8

    /// Tamaño máximo al que se reduce la imagen (lado más largo en puntos × escala)
    private static let maxPixelSize: CGFloat = {
        let screen = UIScreen.main.bounds
        let scale = UIScreen.main.scale
        return max(screen.width, screen.height) * scale
    }()

    // MARK: - Deduplicación de peticiones en vuelo

    private actor InflightCoordinator {
        var tasks: [String: Task<UIImage?, Never>] = [:]

        func existing(for key: String) -> Task<UIImage?, Never>? { tasks[key] }
        func register(_ task: Task<UIImage?, Never>, for key: String) { tasks[key] = task }
        func remove(for key: String) { tasks.removeValue(forKey: key) }
    }

    private static let inflight = InflightCoordinator()

    // MARK: - URLSession optimizada

    /// Sesión dedicada: HTTP/2 multiplexing, cache agresivo en disco, conexiones paralelas.
    static let imageSession: URLSession = {
        let config = URLSessionConfiguration.default
        // Timeouts cortos: falla rápido, no bloquea el scroll
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 10
        // Cache grande en disco: las imágenes se guardan entre sesiones
        config.urlCache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,   // 50 MB en RAM
            diskCapacity: 300 * 1024 * 1024       // 300 MB en disco
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        // Más conexiones simultáneas para Supabase
        config.httpMaximumConnectionsPerHost = 10
        // HTTP/2 multiplexing (por defecto en iOS, pero lo aseguramos)
        config.multipathServiceType = .none
        // Desactivar cookies (no las necesitamos) para reducir overhead
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        // Permitir cargas en celular
        config.allowsCellularAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        return URLSession(configuration: config)
    }()

    // MARK: - Clave de caché por payload

    private static func cacheKey(for payload: CarImageSlot.Payload) -> String {
        switch payload {
        case let .base64(b64):
            return "b64:\(b64.prefix(64).hashValue)"
        case let .publicVehiclesFile(path):
            return "pub:\(path)"
        case let .signed(bucket, path):
            return "signed:\(bucket)/\(path)"
        case let .url(s):
            return "url:\(s)"
        }
    }

    // MARK: - API pública

    static func load(car: Car, auth: AuthViewModel) async -> UIImage? {
        guard let first = car.resolvedImageSlots.first else { return nil }
        return await load(payload: first.payload, auth: auth)
    }

    static func load(payload: CarImageSlot.Payload, auth: AuthViewModel) async -> UIImage? {
        let key = cacheKey(for: payload)

        // 1️⃣ Caché L1 (memoria) — instantáneo
        if let cached = ImageCacheService.shared.image(forKey: key) {
            return cached
        }

        // 2️⃣ Deduplicar peticiones en vuelo
        if let existing = await inflight.existing(for: key) {
            return await existing.value
        }

        let task = Task<UIImage?, Never> {
            let image = await loadWithTimeout(payload: payload, auth: auth)
            if let image {
                ImageCacheService.shared.store(image, forKey: key)
            }
            await inflight.remove(for: key)
            return image
        }
        await inflight.register(task, for: key)

        return await task.value
    }

    // MARK: - Prefetch: precarga las imágenes de coches cercanos al viewport

    /// Llama esto desde `onAppear` de cada card para precargar vecinos.
    /// No bloquea — lanza tareas en background.
    static func prefetch(cars: [Car], around index: Int, auth: AuthViewModel, window: Int = 3) {
        let lo = max(0, index - window)
        let hi = min(cars.count - 1, index + window)
        guard lo <= hi else { return }

        for i in lo...hi {
            let car = cars[i]
            guard let first = car.resolvedImageSlots.first else { continue }
            let key = cacheKey(for: first.payload)
            // Solo prefetch si no está en caché
            if ImageCacheService.shared.image(forKey: key) != nil { continue }

            Task.detached(priority: .utility) {
                _ = await load(payload: first.payload, auth: auth)
            }
        }
    }

    /// Prefetch específico para todos los slots de galería de un coche
    static func prefetchGallery(car: Car, auth: AuthViewModel) {
        for slot in car.resolvedImageSlots {
            let key = cacheKey(for: slot.payload)
            if ImageCacheService.shared.image(forKey: key) != nil { continue }
            Task.detached(priority: .utility) {
                _ = await load(payload: slot.payload, auth: auth)
            }
        }
    }

    // MARK: - Carga con timeout global

    private static func loadWithTimeout(payload: CarImageSlot.Payload, auth: AuthViewModel) async -> UIImage? {
        return await withTaskGroup(of: UIImage?.self) { group in
            group.addTask { await loadFromSource(payload: payload, auth: auth) }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(imageTimeoutSeconds * 1_000_000_000))
                return nil
            }
            for await result in group {
                if let result {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }

    // MARK: - Carga desde fuente

    private static func loadFromSource(payload: CarImageSlot.Payload, auth: AuthViewModel) async -> UIImage? {
        switch payload {
        case let .base64(b64):
            guard let data = Data(base64Encoded: b64, options: [.ignoreUnknownCharacters]) else { return nil }
            return downsample(data: data)

        case let .publicVehiclesFile(path):
            // Carrera: URL pública directa vs SDK download — el primero gana
            return await raceImageLoads([
                {
                    let urlStr = SupabaseClientProvider.publicStorageObjectURL(
                        bucket: SupabaseClientProvider.publicVehiclesBucket, path: path)
                    guard let url = URL(string: urlStr) else { return nil }
                    return await fetchAndDownsample(url: url, auth: auth)
                },
                { try? await downloadFromStorage(bucket: SupabaseClientProvider.publicVehiclesBucket, path: path) },
            ])

        case let .signed(bucket, path):
            return await raceImageLoads([
                // 1. Intentar como URL pública (muchas veces el bucket es público)
                {
                    let urlStr = SupabaseClientProvider.publicStorageObjectURL(bucket: bucket, path: path)
                    guard let url = URL(string: urlStr) else { return nil }
                    return await fetchAndDownsample(url: url, auth: auth)
                },
                // 2. Download directo via SDK
                { try? await downloadFromStorage(bucket: bucket, path: path) },
                // 3. Signed URL como fallback
                {
                    guard let signed = try? await SupabaseClientProvider.shared.storage
                        .from(bucket)
                        .createSignedURL(path: path, expiresIn: 3600) else { return nil }
                    return await fetchAndDownsample(url: signed, auth: auth)
                },
            ])

        case let .url(s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let u = VehicleImageResolution.resolvedHTTPURL(from: t) else { return nil }
            return await fetchAndDownsample(url: u, auth: auth)
        }
    }

    // MARK: - Descarga HTTP + downsampling

    private static func fetchAndDownsample(url: URL, auth: AuthViewModel) async -> UIImage? {
        let accessToken = await MainActor.run { auth.session?.accessToken }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad

        let isSupabase = url.host?.contains("supabase") == true
        if isSupabase {
            request.setValue(SupabaseClientProvider.anonKey, forHTTPHeaderField: "apikey")
            if let token = accessToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            } else {
                request.setValue("Bearer \(SupabaseClientProvider.anonKey)", forHTTPHeaderField: "Authorization")
            }
        }

        do {
            let (data, response) = try await imageSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            return downsample(data: data)
        } catch {
            return nil
        }
    }

    // MARK: - Descarga desde Storage SDK

    private static func downloadFromStorage(bucket: String, path: String) async throws -> UIImage? {
        let data = try await SupabaseClientProvider.shared.storage.from(bucket).download(path: path)
        return downsample(data: data)
    }

    // MARK: - Downsampling: decodifica a tamaño de pantalla, no al tamaño original

    /// Usa `CGImageSource` para decodificar la imagen directamente al tamaño necesario,
    /// evitando asignar memoria para la imagen completa (ej. 4000×3000 → 1290×960).
    /// Esto reduce uso de RAM y tiempo de decodificación drásticamente.
    private static func downsample(data: Data) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,           // No cachear la imagen original
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,  // Decodificar ya (no lazy)
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            // Fallback: decodificación normal
            guard let ui = UIImage(data: data), ui.size.width > 0 else { return nil }
            return ui
        }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Race: múltiples estrategias en paralelo, gana la primera

    private static func raceImageLoads(_ loaders: [@Sendable () async -> UIImage?]) async -> UIImage? {
        return await withTaskGroup(of: UIImage?.self) { group in
            for loader in loaders {
                group.addTask { await loader() }
            }
            for await result in group {
                if let image = result {
                    group.cancelAll()
                    return image
                }
            }
            return nil
        }
    }
}
