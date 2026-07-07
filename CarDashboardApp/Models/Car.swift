import Foundation

struct Car: Identifiable, Hashable {
    let id: UUID
    var name: String
    var model: String
    var plate: String
    var year: Int
    var icon: String
    var isConnected: Bool
    var color: String
    /// URL absoluta lista para descargar (externa o ya resuelta).
    var imageURLString: String?
    /// Solo nombre de archivo con extensión de imagen → `storage.from("vehicles").getPublicURL`.
    var imagePublicVehiclesFileName: String?
    /// Clave dentro del bucket privado (p. ej. `{user_id}/{vehicle_id}/foto.jpg`).
    var imageSignedStoragePath: String?
    var imageSignedStorageBucket: String?
    /// Payload base64 (sin prefijo `data:image/...;base64,`).
    var imageBase64: String?
    /// Galería completa (varias fotos). Si está vacía, se usan los campos de imagen “legacy” de arriba.
    var imageSlots: [CarImageSlot]

    // Campos opcionales (marketplace / ficha); si faltan en la base de datos, la UI muestra texto neutro.
    var brandName: String?
    var listPriceEUR: Double?
    var financedPriceEUR: Double?
    var monthlyPaymentEUR: Double?
    var mileageKm: Int?
    var fuelType: String?
    var bodyType: String?
    var locationText: String?
    var sellerKind: String?
    var sellerRating: Double?
    var dgtLabel: String?
    var powerCv: Int?
    var transmission: String?
    var equipmentSummary: String?
    var exteriorColorLabel: String?
    var onlineListing: Bool?
    var isReservable: Bool?
    /// Marca explícita de vendido (`is_sold`, etc.) si existe en Supabase.
    var isSold: Bool?
    /// Estado de stock (`status`, `vehicle_status`, …) para inferir vendido/reservado.
    var stockStatus: String?

    init(
        id: UUID = UUID(),
        name: String,
        model: String,
        plate: String,
        year: Int,
        icon: String = "car.fill",
        isConnected: Bool = false,
        color: String = "cyan",
        imageURLString: String? = nil,
        imagePublicVehiclesFileName: String? = nil,
        imageSignedStoragePath: String? = nil,
        imageSignedStorageBucket: String? = nil,
        imageBase64: String? = nil,
        imageSlots: [CarImageSlot] = [],
        brandName: String? = nil,
        listPriceEUR: Double? = nil,
        financedPriceEUR: Double? = nil,
        monthlyPaymentEUR: Double? = nil,
        mileageKm: Int? = nil,
        fuelType: String? = nil,
        bodyType: String? = nil,
        locationText: String? = nil,
        sellerKind: String? = nil,
        sellerRating: Double? = nil,
        dgtLabel: String? = nil,
        powerCv: Int? = nil,
        transmission: String? = nil,
        equipmentSummary: String? = nil,
        exteriorColorLabel: String? = nil,
        onlineListing: Bool? = nil,
        isReservable: Bool? = nil,
        isSold: Bool? = nil,
        stockStatus: String? = nil
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.plate = plate
        self.year = year
        self.icon = icon
        self.isConnected = isConnected
        self.color = color
        self.imageURLString = imageURLString
        self.imagePublicVehiclesFileName = imagePublicVehiclesFileName
        self.imageSignedStoragePath = imageSignedStoragePath
        self.imageSignedStorageBucket = imageSignedStorageBucket
        self.imageBase64 = imageBase64
        self.imageSlots = imageSlots
        self.brandName = brandName
        self.listPriceEUR = listPriceEUR
        self.financedPriceEUR = financedPriceEUR
        self.monthlyPaymentEUR = monthlyPaymentEUR
        self.mileageKm = mileageKm
        self.fuelType = fuelType
        self.bodyType = bodyType
        self.locationText = locationText
        self.sellerKind = sellerKind
        self.sellerRating = sellerRating
        self.dgtLabel = dgtLabel
        self.powerCv = powerCv
        self.transmission = transmission
        self.equipmentSummary = equipmentSummary
        self.exteriorColorLabel = exteriorColorLabel
        self.onlineListing = onlineListing
        self.isReservable = isReservable
        self.isSold = isSold
        self.stockStatus = stockStatus
    }

    /// Slots efectivos para la UI: galería o, si no hay, la única imagen legacy.
    var resolvedImageSlots: [CarImageSlot] {
        if !imageSlots.isEmpty { return imageSlots }
        var out: [CarImageSlot] = []
        if let u = imageURLString?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
            if let s = CarImageSlot(classifyingRaw: u) {
                out.append(s)
                return out
            }
        }
        if let f = imagePublicVehiclesFileName?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty {
            out.append(CarImageSlot(payload: .publicVehiclesFile(f)))
            return out
        }
        if let p = imageSignedStoragePath?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            let b = imageSignedStorageBucket?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? SupabaseClientProvider.vehicleMediaBucket
            let clean = p.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            out.append(CarImageSlot(payload: .signed(bucket: b, path: clean)))
            return out
        }
        if let b64 = imageBase64?.trimmingCharacters(in: .whitespacesAndNewlines), !b64.isEmpty {
            let norm = VehicleImageResolution.normalizeBase64Payload(b64)
            if !norm.isEmpty {
                out.append(CarImageSlot(payload: .base64(norm)))
            }
        }
        return out
    }
}
