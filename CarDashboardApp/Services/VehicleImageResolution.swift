import Foundation

/// Resolución de imagen alineada con `vehicle_image_url_resolver` (Dart): HTTP, `vehicles` público (solo archivo),
/// rutas con `/` en bucket privado (`vehicle-media`) para `createSignedURL`, y `data:` / base64.
enum VehicleImageResolution: Equatable {
    case absoluteURL(URL)
    /// Reserva la cadena http(s) aunque `URL(string:)` estricto falle (URLs con espacios, Unicode, etc.).
    case absoluteURLRawString(String)
    case publicVehiclesFileName(String)
    case signedStorage(bucket: String, path: String)
    case inlineBase64(String)

    /// URL http(s) lista para `URLRequest`, con corrección de caracteres inválidos (iOS 17+).
    static func resolvedHTTPURL(from string: String) -> URL? {
        let t = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if let u = URL(string: t, encodingInvalidCharacters: true),
           let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return u
        }
        if let u = URL(string: t),
           let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return u
        }
        return nil
    }

    private static let imageExtensionPattern =
        try? NSRegularExpression(pattern: #"\.(jpe?g|png|webp|gif|avif)$"#, options: [.caseInsensitive])

    static func classify(raw: String) -> VehicleImageResolution? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }

        if t.lowercased().hasPrefix("http://") || t.lowercased().hasPrefix("https://") {
            if let u = Self.resolvedHTTPURL(from: t) {
                return .absoluteURL(u)
            }
            return .absoluteURLRawString(t)
        }
        if t.hasPrefix("//") {
            if let u = Self.resolvedHTTPURL(from: "https:\(t)") {
                return .absoluteURL(u)
            }
            return .absoluteURLRawString("https:\(t)")
        }
        if t.lowercased().hasPrefix("data:image") {
            if let b64 = extractBase64(fromDataURL: t) { return .inlineBase64(b64) }
        }

        let noSlash = !t.contains("/")
        if noSlash, hasImageExtension(t) {
            return .publicVehiclesFileName(t)
        }

        let path = t.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty else { return nil }
        let bucket = SupabaseClientProvider.vehicleMediaBucket
        return .signedStorage(bucket: bucket, path: path)
    }

    private static func hasImageExtension(_ s: String) -> Bool {
        guard let regex = imageExtensionPattern else { return false }
        let range = NSRange(s.startIndex..., in: s)
        return regex.firstMatch(in: s, options: [], range: range) != nil
    }

    private static func extractBase64(fromDataURL t: String) -> String? {
        if let r = t.range(of: "base64,", options: .caseInsensitive) {
            return normalizeBase64Payload(String(t[r.upperBound...]))
        }
        return nil
    }

    static func normalizeBase64Payload(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    /// Heurística para encontrar URLs/rutas de imagen en columnas no mapeadas.
    static func looksLikeImageReference(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= 4096 else { return false }
        let l = t.lowercased()
        if l.hasPrefix("http://") || l.hasPrefix("https://") { return true }
        if l.hasPrefix("data:image") { return true }
        let ext = #"\.(jpe?g|png|webp|gif|avif|bmp)(\?|#|$)"#
        if t.range(of: ext, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        if t.contains("/storage/v1/object/"), t.contains("/") { return true }
        return false
    }

    static func isPlainPublicVehicleFileName(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.contains("/") else { return false }
        return hasImageExtensionStatic(t)
    }

    private static func hasImageExtensionStatic(_ s: String) -> Bool {
        guard let regex = imageExtensionPattern else { return false }
        let range = NSRange(s.startIndex..., in: s)
        return regex.firstMatch(in: s, options: [], range: range) != nil
    }
}
