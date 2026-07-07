import Foundation

/// Descarga bytes de audio del CRM (WhatsApp/Instagram), con auth si la URL es del backend.
enum CrmAudioLoader {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 120
        config.urlCache = URLCache(memoryCapacity: 10 * 1024 * 1024, diskCapacity: 60 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    static func download(url: URL, accessToken: String?) async throws -> Data {
        if url.scheme?.lowercased() == "data" {
            let raw = url.absoluteString
            guard let comma = raw.firstIndex(of: ",") else {
                throw URLError(.badURL)
            }
            let payload = String(raw[raw.index(after: comma)...])
            guard let data = Data(base64Encoded: payload) else {
                throw URLError(.cannotDecodeContentData)
            }
            return data
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        if needsAuthorization(for: url), let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200 ... 299).contains(http.statusCode),
              !data.isEmpty
        else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private static func needsAuthorization(for url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return url.path.hasPrefix("/api/")
        }
        return host.contains("carhubackend") || host.contains("carhub365")
    }
}
