import Foundation

// MARK: - Mapeo columnas PostgREST → tabla `vehicles`

/// Nombres reales de columnas en el INSERT. Por defecto coincide con el esquema típico Dealcar / `make`·`model`·`kilometers`·`fuel`.
/// Sobrescribe en `DeveloperSettings.local.xcconfig` con `VEHICLES_COL_*` si tu tabla usa otros nombres.
enum VehiclesInsertColumnMap {
    private static func resolved(_ plistKey: String, default def: String) -> String {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: plistKey) as? String else { return def }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return def }
        if t.hasPrefix("$(") { return def }
        return t
    }

    static var id: String { resolved("VEHICLES_COL_ID", default: "id") }
    static var userId: String { resolved("VEHICLES_COL_USER_ID", default: "user_id") }
    static var organizationId: String { resolved("VEHICLES_COL_ORGANIZATION_ID", default: "organization_id") }
    static var companyId: String { resolved("VEHICLES_COL_COMPANY_ID", default: "company_id") }
    static var brand: String { resolved("VEHICLES_COL_BRAND", default: "make") }
    static var model: String { resolved("VEHICLES_COL_MODEL", default: "model") }
    static var year: String { resolved("VEHICLES_COL_YEAR", default: "year") }
    static var licensePlate: String { resolved("VEHICLES_COL_LICENSE_PLATE", default: "license_plate") }
    static var price: String { resolved("VEHICLES_COL_PRICE", default: "price") }
    static var mileage: String { resolved("VEHICLES_COL_MILEAGE", default: "kilometers") }
    static var powerCv: String { resolved("VEHICLES_COL_POWER_CV", default: "power") }
    static var fuelType: String { resolved("VEHICLES_COL_FUEL_TYPE", default: "fuel") }
    static var transmission: String { resolved("VEHICLES_COL_TRANSMISSION", default: "transmission") }
    /// Columna para la URL de portada tras subir fotos a Storage (listado marketplace solo lee columnas JSON).
    static var mainImageURL: String { resolved("VEHICLES_COL_MAIN_IMAGE_URL", default: "main_image_url") }
    static var vin: String { resolved("VEHICLES_COL_VIN", default: "vin") }
    static var color: String { resolved("VEHICLES_COL_COLOR", default: "color") }
    static var dgtLabel: String { resolved("VEHICLES_COL_DGT_LABEL", default: "dgt_label") }
    static var purchasePrice: String { resolved("VEHICLES_COL_PURCHASE_PRICE", default: "purchase_price") }
    static var marketPrice: String { resolved("VEHICLES_COL_MARKET_PRICE", default: "market_price") }
    static var financedPrice: String { resolved("VEHICLES_COL_FINANCED_PRICE", default: "financed_price") }
    static var listingDescription: String { resolved("VEHICLES_COL_LISTING_DESCRIPTION", default: "listing_description") }
    static var listingExtra: String { resolved("VEHICLES_COL_LISTING_EXTRA", default: "listing_extra") }
}

/// `CodingKey` dinámico para serializar el insert con nombres de columna configurables.
struct VehiclesInsertDynamicKey: CodingKey {
    var stringValue: String
    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
}
