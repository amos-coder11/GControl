import Foundation

// MARK: - JSON auxiliar en `listing_extra` (jsonb)

/// Campos que no van como columnas escalares propias o que agrupan listas (equipamiento, portales).
struct VehicleListingExtraJSON: Codable, Sendable, Equatable {
    var acquisitionCategory: String?
    var vatDeductible: String?
    var singleOwner: Bool?
    var serviceBook: Bool?
    var officialServiceBook: Bool?
    var nationalVehicle: Bool?
    var dgtLabelNote: String?
    var storeLocation: String?
    var equipmentCodes: [String]?
    var ownerName: String?
    var ownerPhone: String?
    var ownerEmail: String?
    var ownerZone: String?
    var ownerCanVisitOffice: Bool?
    var publishAllPlatforms: Bool?
    var publishAutoScout: Bool?
    var publishCochesNet: Bool?
    var publishWallapop: Bool?
    var publishOwnWeb: Bool?
    var lastServiceKm: Int?
    var lastServiceYear: Int?

    enum CodingKeys: String, CodingKey {
        case acquisitionCategory = "acquisition_category"
        case vatDeductible = "vat_deductible"
        case singleOwner = "single_owner"
        case serviceBook = "service_book"
        case officialServiceBook = "official_service_book"
        case nationalVehicle = "national_vehicle"
        case dgtLabelNote = "dgt_label_note"
        case storeLocation = "store_location"
        case equipmentCodes = "equipment_codes"
        case ownerName = "owner_name"
        case ownerPhone = "owner_phone"
        case ownerEmail = "owner_email"
        case ownerZone = "owner_zone"
        case ownerCanVisitOffice = "owner_can_visit_office"
        case publishAllPlatforms = "publish_all_platforms"
        case publishAutoScout = "publish_autoscout"
        case publishCochesNet = "publish_coches_net"
        case publishWallapop = "publish_wallapop"
        case publishOwnWeb = "publish_own_web"
        case lastServiceKm = "last_service_km"
        case lastServiceYear = "last_service_year"
    }
}

// MARK: - Carga útil para INSERT desde la app

/// Datos de ficha + anuncio que mapean a columnas PostgREST y a `listing_extra`.
struct VehicleAppListingPayload: Sendable {
    var brand: String
    var model: String
    var year: Int
    var licensePlate: String?
    /// Precio de venta / PVP (columna `price` habitual).
    var salePriceEUR: Double?
    var purchasePriceEUR: Double?
    var marketPriceEUR: Double?
    var financedPriceEUR: Double?
    var mileageKm: Int?
    var fuelType: String?
    var transmission: String?
    var vin: String?
    var exteriorColor: String?
    var listingDescription: String?
    /// Etiqueta ambiental (p. ej. C, ECO) si la tienes aparte del combustible.
    var dgtLabel: String?
    var listingExtra: VehicleListingExtraJSON?
}
