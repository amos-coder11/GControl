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

    /// Todas las URLs/rutas reconocibles en la galería (orden de recorrido).
    func allImageLikeStrings() -> [String] {
        switch self {
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard VehicleImageResolution.looksLikeImageReference(t) else { return [] }
            return [t]
        case .array(let items):
            return items.flatMap { $0.allImageLikeStrings() }
        case .object(let dict):
            let priority = [
                "url", "src", "href", "path", "signed_url", "public_url", "image_url", "thumbnail_url",
                "storage_path", "key", "publicUrl", "signedUrl", "thumbnailUrl",
            ]
            var out: [String] = []
            for pk in priority {
                for (ik, iv) in dict where ik.lowercased() == pk.lowercased() {
                    out.append(contentsOf: iv.allImageLikeStrings())
                }
            }
            for (_, v) in dict {
                out.append(contentsOf: v.allImageLikeStrings())
            }
            return out
        case .unknown:
            return []
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
    /// Valor crudo de imagen (`image_url`, galería, etc.) — primera / principal.
    var imageSourceRaw: String?
    /// Todas las referencias de imagen encontradas en columnas y JSON (orden conservado).
    var imageGalleryRaws: [String] = []
    /// `image_base64` en Postgres.
    var imageBase64Raw: String?
    var storagePathColumn: String?
    var storageBucketColumn: String?

    /// Campos opcionales de ficha / marketplace (columnas habituales en Supabase).
    var listPriceEUR: Double?
    var financedPriceEUR: Double?
    var monthlyPaymentEUR: Double?
    var mileageKm: Int?
    var fuelTypeDecoded: String?
    var vehicleBodyType: String?
    var locationDecoded: String?
    var sellerKindDecoded: String?
    var sellerRatingDecoded: Double?
    var dgtLabelDecoded: String?
    var powerCvDecoded: Int?
    var transmissionDecoded: String?
    var equipmentDecoded: String?
    var exteriorColorDecoded: String?
    var onlineListingDecoded: Bool?
    var reservableDecoded: Bool?

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

    private static func optDouble(_ c: KeyedDecodingContainer<DynamicKey>, _ keys: [String]) -> Double? {
        for k in keys {
            if let d = try? c.decodeIfPresent(Double.self, forKey: dkey(k)) { return d }
            if let i = try? c.decodeIfPresent(Int.self, forKey: dkey(k)) { return Double(i) }
            if let s = try? c.decodeIfPresent(String.self, forKey: dkey(k)) {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleaned = t
                    .replacingOccurrences(of: "€", with: "")
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: ",", with: ".")
                if let d = Double(cleaned) { return d }
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

    private static func allStringsInArrays(_ c: KeyedDecodingContainer<DynamicKey>, _ keys: [String]) -> [String] {
        var out: [String] = []
        for k in keys {
            guard let arr = try? c.decodeIfPresent([String].self, forKey: dkey(k)) else { continue }
            for s in arr {
                if let t = trimmedNonEmpty(s) { out.append(t) }
            }
        }
        return out
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

    private static func allURLsFromObjectArrays(_ c: KeyedDecodingContainer<DynamicKey>, _ keys: [String]) -> [String] {
        var out: [String] = []
        for k in keys {
            guard let rows = try? c.decodeIfPresent([[String: String]].self, forKey: dkey(k)) else { continue }
            for dict in rows {
                let candidates = ["url", "src", "href", "publicUrl", "public_url", "signedUrl", "signed_url"]
                for ck in candidates {
                    if let s = dict[ck], let t = trimmedNonEmpty(s) { out.append(t) }
                }
            }
        }
        return out
    }

    private static func scavengeAllImageLikeStrings(from c: KeyedDecodingContainer<DynamicKey>) -> [String] {
        var out: [String] = []
        for key in c.allKeys {
            let kn = key.stringValue.lowercased()
            guard interestingMediaKeyName(kn) else { continue }
            guard let s = try? c.decode(String.self, forKey: key), s.count <= 4096,
                  let t = trimmedNonEmpty(s),
                  VehicleImageResolution.looksLikeImageReference(t) else { continue }
            out.append(t)
        }
        return out
    }

    /// Orden estable, sin duplicados (comparación sin distinguir mayúsculas).
    static func mergeImageGalleryRaws(_ a: [String], _ b: [String]) -> [String] {
        uniqueImageStrings(a + b)
    }

    private static func uniqueImageStrings(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for s in items {
            guard let t = trimmedNonEmpty(s) else { continue }
            let k = t.lowercased()
            guard !seen.contains(k) else { continue }
            seen.insert(k)
            out.append(t)
        }
        return out
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

        var galleryCandidates: [String] = []
        if let t = trimmedNonEmpty(img) {
            galleryCandidates.append(t)
        }
        galleryCandidates.append(contentsOf: Self.allStringsInArrays(c, [
            "photos", "images", "imagenes", "image_urls", "imageUrls", "gallery", "media_urls", "mediaUrls",
            "attachments", "pictures", "fotos", "photo_urls", "photoUrls", "gallery_urls",
            "storage_paths", "storagePaths", "image_paths", "imagePaths", "media_paths", "mediaPaths",
        ]))
        galleryCandidates.append(contentsOf: Self.allURLsFromObjectArrays(c, [
            "photos", "images", "imagenes", "gallery", "media", "attachments",
        ]))
        for nk in ["cover", "thumbnail", "hero_image", "heroImage", "media"] {
            guard let dict = try? c.decodeIfPresent([String: String].self, forKey: Self.dkey(nk)) else { continue }
            let candidates = ["url", "src", "href", "publicUrl", "public_url", "signedUrl", "signed_url"]
            for ck in candidates {
                if let s = dict[ck], let t = trimmedNonEmpty(s) { galleryCandidates.append(t) }
            }
        }
        for gk in Self.looseGalleryColumnNames {
            guard let key = DynamicKey(stringValue: gk) else { continue }
            guard let loose = try? c.decode(LooseGalleryJSON.self, forKey: key) else { continue }
            galleryCandidates.append(contentsOf: loose.allImageLikeStrings())
        }
        galleryCandidates.append(contentsOf: Self.scavengeAllImageLikeStrings(from: c))
        let scalarImageColumns = [
            "image_url", "photo_url", "thumbnail_url", "cover_url", "picture",
            "imagen_url", "main_image", "image", "foto", "url_foto", "url_imagen",
            "foto_url", "car_image", "vehicle_image", "imageUrl", "photoUrl", "thumbnailUrl",
            "coverImage", "cover_image", "avatar_url", "avatarUrl", "media_url",
        ]
        for col in scalarImageColumns {
            if let s = Self.optString(c, [col]) {
                galleryCandidates.append(s)
            }
        }
        imageGalleryRaws = Self.uniqueImageStrings(galleryCandidates)

        listPriceEUR = Self.optDouble(c, [
            "price", "precio", "cash_price", "list_price", "pvp", "amount", "price_eur", "priceEUR", "asking_price",
        ])
        if listPriceEUR == nil, let cents = Self.optInt(c, ["price_cents", "priceCents", "precio_centimos"]) {
            listPriceEUR = Double(cents) / 100.0
        }

        financedPriceEUR = Self.optDouble(c, ["financed_price", "precio_financiado", "finance_price", "financedPrice"])
        monthlyPaymentEUR = Self.optDouble(c, [
            "monthly_payment", "cuota_mensual", "cuota", "monthly_installment", "monthlyPayment",
        ])
        mileageKm = Self.optInt(c, ["mileage", "kilometers", "km", "odometer", "odometro", "kilometraje", "mileage_km"])

        fuelTypeDecoded = Self.optString(c, [
            "fuel_type", "fuelType", "combustible", "motor", "engine_type", "engineType", "tipo_motor",
        ])
        vehicleBodyType = Self.optString(c, [
            "body_type", "bodyType", "vehicle_type", "vehicleType", "tipo_coche", "tipo", "category", "car_type",
        ])
        locationDecoded = Self.optString(c, [
            "city", "location", "ubicacion", "ciudad", "province", "provincia", "town",
        ])

        let sellerRaw = Self.optString(c, [
            "seller_type", "sellerType", "vendedor", "dealer_type", "tipo_vendedor", "seller_kind",
        ])
        sellerKindDecoded = Self.normalizeSellerKind(sellerRaw)
        sellerRatingDecoded = Self.optDouble(c, ["seller_rating", "rating", "stars", "valoracion", "sellerRating"])

        dgtLabelDecoded = Self.optString(c, [
            "dgt_label", "dgt", "etiqueta_dgt", "environmental_label", "eco_label",
        ])
        powerCvDecoded = Self.optInt(c, ["power_cv", "cv", "horsepower", "hp", "potencia", "power"])
        transmissionDecoded = Self.optString(c, ["transmission", "cambio", "gearbox"])
        equipmentDecoded = Self.optString(c, ["equipment", "equipamiento", "features", "extras"])
        exteriorColorDecoded = Self.optString(c, [
            "body_color", "exterior_color", "paint_color", "color_carroceria", "car_color",
        ])

        onlineListingDecoded = Self.optBool(c, [
            "online_listing", "online_only", "servicio_online", "web_listing", "onlineListing",
        ])
        reservableDecoded = Self.optBool(c, ["reservable", "is_reservable", "can_reserve"])
    }

    private static func normalizeSellerKind(_ raw: String?) -> String? {
        guard let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        let l = t.lowercased()
        if l.contains("prof") || l.contains("dealer") || l.contains("conces") { return "Profesional" }
        if l.contains("part") || l.contains("private") || l.contains("partic") { return "Particular" }
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    private func buildImageSlots() -> [CarImageSlot] {
        var slots: [CarImageSlot] = []
        var seen = Set<String>()
        func appendSlot(_ slot: CarImageSlot) {
            let k = slot.id.lowercased()
            guard seen.insert(k).inserted else { return }
            slots.append(slot)
        }
        func appendRaw(_ raw: String?) {
            guard let raw = trimmedNonEmpty(raw), let slot = CarImageSlot(classifyingRaw: raw) else { return }
            appendSlot(slot)
        }

        for raw in imageGalleryRaws {
            appendRaw(raw)
        }
        appendRaw(imageSourceRaw)

        if let rawB64 = trimmedNonEmpty(imageBase64Raw) {
            let t = rawB64.trimmingCharacters(in: .whitespacesAndNewlines)
            if let slot = CarImageSlot(classifyingRaw: t) {
                appendSlot(slot)
            } else {
                let norm = VehicleImageResolution.normalizeBase64Payload(t)
                if let t2 = trimmedNonEmpty(norm) {
                    appendSlot(CarImageSlot(payload: .base64(t2)))
                }
            }
        }

        if let p0 = trimmedNonEmpty(storagePathColumn) {
            let pClean = p0.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let bucketLower = trimmedNonEmpty(storageBucketColumn)?.lowercased()
                ?? SupabaseClientProvider.vehicleMediaBucket.lowercased()
            let vehiclesLower = SupabaseClientProvider.publicVehiclesBucket.lowercased()
            if bucketLower == vehiclesLower {
                appendSlot(CarImageSlot(payload: .publicVehiclesFile(pClean)))
            } else {
                let b = trimmedNonEmpty(storageBucketColumn) ?? SupabaseClientProvider.vehicleMediaBucket
                appendSlot(CarImageSlot(payload: .signed(bucket: b, path: pClean)))
            }
        }

        return slots
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

        let imageSlots = buildImageSlots()

        print("🚗 [\(displayName)] imageGalleryRaws=\(imageGalleryRaws.count) imageSlots=\(imageSlots.count) | storagePathColumn=\(storagePathColumn ?? "nil")")

        var urlString: String?
        var publicVehiclesFile: String?
        var signedPath: String?
        var signedBucket: String?
        var b64: String?

        if let s0 = imageSlots.first {
            switch s0.payload {
            case let .url(u):
                urlString = u
            case let .publicVehiclesFile(f):
                publicVehiclesFile = f
            case let .signed(bucket, path):
                signedBucket = bucket
                signedPath = path
            case let .base64(payload):
                b64 = payload
            }
        }

        let brandResolved = firstNonEmptyString([brand, make])

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
            imageBase64: b64,
            imageSlots: imageSlots,
            brandName: brandResolved,
            listPriceEUR: listPriceEUR,
            financedPriceEUR: financedPriceEUR,
            monthlyPaymentEUR: monthlyPaymentEUR,
            mileageKm: mileageKm,
            fuelType: trimmedNonEmpty(fuelTypeDecoded),
            bodyType: trimmedNonEmpty(vehicleBodyType),
            locationText: trimmedNonEmpty(locationDecoded),
            sellerKind: trimmedNonEmpty(sellerKindDecoded),
            sellerRating: sellerRatingDecoded,
            dgtLabel: trimmedNonEmpty(dgtLabelDecoded),
            powerCv: powerCvDecoded,
            transmission: trimmedNonEmpty(transmissionDecoded),
            equipmentSummary: trimmedNonEmpty(equipmentDecoded),
            exteriorColorLabel: trimmedNonEmpty(exteriorColorDecoded),
            onlineListing: onlineListingDecoded,
            isReservable: reservableDecoded
        )
        print("✅ [\(displayName)] Car image config → slots=\(imageSlots.count) url=\(urlString ?? "nil") | publicFile=\(publicVehiclesFile ?? "nil") | signedPath=\(signedPath ?? "nil") | hasImagePayload=\(car.hasImagePayload)")
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
