import Foundation

private struct DynamicKey: CodingKey {
    var stringValue: String
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
}

/// JSON arbitrario (galerías `jsonb`) para extraer la primera URL/ruta de imagen.
private enum LooseGalleryJSON: Decodable, Sendable {
    case string(String)
    case array([LooseGalleryJSON])
    case object([String: LooseGalleryJSON])
    case unknown

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .unknown
            return
        }
        if let s = try? c.decode(String.self) {
            self = .string(s)
            return
        }
        if let a = try? c.decode([LooseGalleryJSON].self) {
            self = .array(a)
            return
        }
        if let o = try? c.decode([String: LooseGalleryJSON].self) {
            self = .object(o)
            return
        }
        if let _ = try? c.decode(Double.self) {
            self = .unknown
            return
        }
        if let _ = try? c.decode(Bool.self) {
            self = .unknown
            return
        }
        self = .unknown
    }

    func firstImageLikeString() -> String? {
        switch self {
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return VehicleImageResolution.looksLikeImageReference(t) ? t : nil
        case .array(let items):
            for item in items {
                if let s = item.firstImageLikeString() { return s }
            }
            return nil
        case .object(let dict):
            let priority = [
                "url", "src", "href", "path", "signed_url", "public_url", "image_url", "thumbnail_url",
                "storage_path", "key", "publicUrl", "signedUrl", "thumbnailUrl",
            ]
            for pk in priority {
                for (ik, iv) in dict where ik.lowercased() == pk.lowercased() {
                    if let s = iv.firstImageLikeString() { return s }
                }
            }
            for (_, v) in dict {
                if let s = v.firstImageLikeString() { return s }
            }
            return nil
        case .unknown:
            return nil
        }
    }
}

/// Fila de `public.vehicles`. Decodificación flexible: varios nombres de columna y arrays JSON (`photos`, etc.).
struct VehicleRow: Decodable, Sendable {
    let id: UUID
    var name: String?
    var nickname: String?
    var title: String?
    var label: String?
    var vehicle_name: String?
    var nombre: String?
    var brand: String?
    var make: String?
    var model: String?
    var plate: String?
    var license_plate: String?
    var matricula: String?
    var year: Int?
    var is_connected: Bool?
    var icon: String?
    var color: String?
    /// Valor crudo de imagen (`image_url`, galería, etc.).
    var imageSourceRaw: String?
    /// `image_base64` en Postgres.
    var imageBase64Raw: String?
    var storagePathColumn: String?
    var storageBucketColumn: String?

    private static let palette = ["cyan", "orange", "mint"]

    private static let looseGalleryColumnNames = [
        "images", "photos", "imagenes", "gallery", "media", "attachments", "pictures",
        "imageGallery", "image_gallery", "imageUrls", "image_urls", "photo_urls",
        "media_urls", "files", "assets",
    ]

    private static func dkey(_ s: String) -> DynamicKey { DynamicKey(stringValue: s)! }

    private static func optString(_ c: KeyedDecodingContainer<DynamicKey>, _ keys: [String]) -> String? {
        for k in keys {
            guard let s = try? c.decodeIfPresent(String.self, forKey: dkey(k)) else { continue }
            if let t = trimmedNonEmpty(s) { return t }
        }
        return nil
    }

    private static func optInt(_ c: KeyedDecodingContainer<DynamicKey>, _ keys: [String]) -> Int? {
        for k in keys {
            if let i = try? c.decodeIfPresent(Int.self, forKey: dkey(k)) { return i }
            if let s = try? c.decodeIfPresent(String.self, forKey: dkey(k)),
               let i = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return i
            }
        }
        return nil
    }

    private static func optBool(_ c: KeyedDecodingContainer<DynamicKey>, _ keys: [String]) -> Bool? {
        for k in keys {
            if let b = try? c.decodeIfPresent(Bool.self, forKey: dkey(k)) { return b }
            if let s = try? c.decodeIfPresent(String.self, forKey: dkey(k)) {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if ["1", "true", "t", "si", "sí", "yes"].contains(t) { return true }
                if ["0", "false", "f", "no"].contains(t) { return false }
            }
        }
        return nil
    }

    private static func firstStringInArrays(_ c: KeyedDecodingContainer<DynamicKey>, _ keys: [String]) -> String? {
        for k in keys {
            guard let arr = try? c.decodeIfPresent([String].self, forKey: dkey(k)) else { continue }
            if let f = arr.compactMap({ trimmedNonEmpty($0) }).first { return f }
        }
        return nil
    }

    private static func urlFromNestedObjects(_ c: KeyedDecodingContainer<DynamicKey>, _ keys: [String]) -> String? {
        for k in keys {
            guard let dict = try? c.decodeIfPresent([String: String].self, forKey: dkey(k)) else { continue }
            let candidates = ["url", "src", "href", "publicUrl", "public_url", "signedUrl", "signed_url"]
            for ck in candidates {
                if let s = dict[ck], let t = trimmedNonEmpty(s) { return t }
            }
        }
        return nil
    }

    private static func firstURLFromObjectArrays(_ c: KeyedDecodingContainer<DynamicKey>, _ keys: [String]) -> String? {
        for k in keys {
            guard let rows = try? c.decodeIfPresent([[String: String]].self, forKey: dkey(k)) else { continue }
            for dict in rows {
                let candidates = ["url", "src", "href", "publicUrl", "public_url", "signedUrl", "signed_url"]
                for ck in candidates {
                    if let s = dict[ck], let t = trimmedNonEmpty(s) { return t }
                }
            }
        }
        return nil
    }

    private static func decodeId(_ c: KeyedDecodingContainer<DynamicKey>) throws -> UUID {
        let k = dkey("id")
        if let u = try? c.decode(UUID.self, forKey: k) { return u }
        if let s = try? c.decode(String.self, forKey: k) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if let u = UUID(uuidString: t) { return u }
        }
        throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "id no es un UUID válido"))
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        id = try Self.decodeId(c)

        name = Self.optString(c, ["name", "display_name", "displayName"])
        nickname = Self.optString(c, ["nickname", "nick", "alias"])
        title = Self.optString(c, ["title", "titulo"])
        label = Self.optString(c, ["label", "etiqueta"])
        vehicle_name = Self.optString(c, ["vehicle_name", "vehicleName", "car_name", "carName"])
        nombre = Self.optString(c, ["nombre", "nombre_corto", "nombreCorto"])
        brand = Self.optString(c, ["brand", "marca", "manufacturer"])
        make = Self.optString(c, ["make", "fabricante"])
        model = Self.optString(c, ["model", "modelo", "model_name", "modelName"])
        plate = Self.optString(c, ["plate", "plates"])
        license_plate = Self.optString(c, ["license_plate", "licensePlate"])
        matricula = Self.optString(c, ["matricula", "matrícula", "registration"])
        year = Self.optInt(c, ["year", "model_year", "modelYear", "anio", "año"])

        is_connected = Self.optBool(c, ["is_connected", "isConnected", "connected", "online"])
        icon = Self.optString(c, ["icon", "icon_sf_symbol", "sf_symbol"])
        color = Self.optString(c, ["color", "accent", "theme_color"])

        var img = Self.optString(c, ["image_url"])
        if img == nil {
            img = Self.optString(c, [
                "photo_url", "thumbnail_url", "cover_url", "picture",
                "imagen_url", "main_image", "image", "foto", "url_foto", "url_imagen",
                "foto_url", "car_image", "vehicle_image", "imageUrl", "photoUrl", "thumbnailUrl",
                "coverImage", "cover_image", "avatar_url", "avatarUrl", "media_url", "src", "photo",
            ])
        }
        if img == nil { img = Self.firstStringInArrays(c, ["photos", "images", "imagenes", "image_urls", "imageUrls", "gallery"]) }
        if img == nil { img = Self.firstURLFromObjectArrays(c, ["photos", "images", "imagenes", "gallery"]) }
        if img == nil { img = Self.urlFromNestedObjects(c, ["cover", "thumbnail", "hero_image", "heroImage", "media"]) }

        if img == nil {
            for gk in Self.looseGalleryColumnNames {
                guard let key = DynamicKey(stringValue: gk) else { continue }
                if let loose = try? c.decode(LooseGalleryJSON.self, forKey: key),
                   let found = loose.firstImageLikeString() {
                    img = found
                    break
                }
            }
        }
        if img == nil { img = Self.scavengeImageLikeStrings(from: c) }

        imageSourceRaw = img
        imageBase64Raw = Self.optString(c, ["image_base64", "imageBase64"])
        storagePathColumn = Self.optString(c, [
            "storage_path", "media_path", "object_path", "file_path", "storage_key",
            "object_key", "image_path", "primary_image_path",
        ])
        storageBucketColumn = Self.optString(c, [
            "storage_bucket", "bucket", "bucket_id", "media_bucket", "storageBucket",
        ])
    }

    func toCar(index: Int) -> Car {
        let modelText = trimmedNonEmpty(model) ?? "—"
        let displayName = resolvedDisplayName(modelFallback: modelText)

        let plateText = firstNonEmptyString([
            plate, license_plate, matricula,
        ]) ?? "—"

        let y = year ?? Calendar.current.component(.year, from: Date())
        let connected = is_connected ?? false
        let iconName = trimmedNonEmpty(icon) ?? "car.fill"
        let accent = trimmedNonEmpty(color)
            ?? Self.palette[index % Self.palette.count]

        var urlString: String?
        var publicVehiclesFile: String?
        var signedPath: String?
        var signedBucket: String?
        var b64: String?

        // 🔍 DEBUG: Log raw image data from DB
        print("🚗 [\(displayName)] imageSourceRaw=\(imageSourceRaw ?? "nil") | storagePathColumn=\(storagePathColumn ?? "nil") | storageBucketColumn=\(storageBucketColumn ?? "nil") | imageBase64Raw=\(imageBase64Raw == nil ? "nil" : "(\(imageBase64Raw!.count) chars)")")

        if let raw = trimmedNonEmpty(imageSourceRaw), let kind = VehicleImageResolution.classify(raw: raw) {
            print("🔎 [\(displayName)] imageSourceRaw classified as: \(kind)")
            switch kind {
            case .absoluteURL(let u):
                urlString = u.absoluteString
            case .publicVehiclesFileName(let name):
                publicVehiclesFile = name
            case .signedStorage(let bucket, let path):
                signedBucket = bucket
                signedPath = path
            case .inlineBase64(let payload):
                b64 = payload
            }
        } else if let raw = trimmedNonEmpty(imageSourceRaw) {
            print("⚠️ [\(displayName)] imageSourceRaw could NOT be classified: '\(raw)'")
        }

        if urlString == nil, publicVehiclesFile == nil, signedPath == nil, b64 == nil,
           let rawB64 = trimmedNonEmpty(imageBase64Raw) {
            let t = rawB64.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.lowercased().hasPrefix("data:image"),
               let kind = VehicleImageResolution.classify(raw: t),
               case let .inlineBase64(payload) = kind {
                b64 = payload
            } else {
                b64 = VehicleImageResolution.normalizeBase64Payload(t)
            }
        }

        if urlString == nil, publicVehiclesFile == nil, signedPath == nil, b64 == nil,
           let p0 = trimmedNonEmpty(storagePathColumn) {
            let pClean = p0.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let bucketLower = trimmedNonEmpty(storageBucketColumn)?.lowercased()
                ?? SupabaseClientProvider.vehicleMediaBucket.lowercased()
            let vehiclesLower = SupabaseClientProvider.publicVehiclesBucket.lowercased()
            if bucketLower == vehiclesLower {
                publicVehiclesFile = pClean
            } else {
                signedPath = pClean
                signedBucket = trimmedNonEmpty(storageBucketColumn) ?? SupabaseClientProvider.vehicleMediaBucket
            }
        }

        let car = Car(
            id: id,
            name: displayName,
            model: modelText,
            plate: plateText,
            year: y,
            icon: iconName,
            isConnected: connected,
            color: accent,
            imageURLString: urlString,
            imagePublicVehiclesFileName: publicVehiclesFile,
            imageSignedStoragePath: signedPath,
            imageSignedStorageBucket: signedBucket,
            imageBase64: b64
        )
        print("✅ [\(displayName)] Car image config → url=\(urlString ?? "nil") | publicFile=\(publicVehiclesFile ?? "nil") | signedPath=\(signedPath ?? "nil") | signedBucket=\(signedBucket ?? "nil") | b64=\(b64 == nil ? "nil" : "yes") | hasImagePayload=\(car.hasImagePayload)")
        return car
    }

    private static func scavengeImageLikeStrings(from c: KeyedDecodingContainer<DynamicKey>) -> String? {
        for key in c.allKeys {
            let kn = key.stringValue.lowercased()
            guard interestingMediaKeyName(kn) else { continue }
            guard let s = try? c.decode(String.self, forKey: key), s.count <= 4096,
                  let t = trimmedNonEmpty(s),
                  VehicleImageResolution.looksLikeImageReference(t) else { continue }
            return t
        }
        return nil
    }

    private static func interestingMediaKeyName(_ kn: String) -> Bool {
        let hints = [
            "image", "photo", "picture", "thumb", "cover", "avatar", "media", "gallery",
            "foto", "imagen", "asset", "banner", "hero", "file", "storage", "url", "path",
        ]
        return hints.contains { kn.contains($0) }
    }

    private func resolvedDisplayName(modelFallback: String) -> String {
        if let t = firstNonEmptyString([
            name, nickname, title, label, vehicle_name, nombre,
        ]) {
            return t
        }

        let brandish = firstNonEmptyString([brand, make])
        if let b = brandish, modelFallback != "—" {
            let m = modelFallback
            if m.localizedCaseInsensitiveContains(b) { return m }
            return "\(b) \(m)"
        }
        if let b = brandish { return b }
        if modelFallback != "—" { return modelFallback }
        return "Sin nombre"
    }
}

private func trimmedNonEmpty(_ s: String?) -> String? {
    guard let t0 = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t0.isEmpty else { return nil }
    return t0
}

private func firstNonEmptyString(_ strings: [String?]) -> String? {
    for s in strings {
        if let t = trimmedNonEmpty(s) { return t }
    }
    return nil
}
