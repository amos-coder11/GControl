import Foundation

// MARK: - Segmento inventario (Todos / Vendidos / Reservados)

enum CarsInventorySegment: String, CaseIterable, Identifiable {
    case all
    case sold
    case reserved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Todos"
        case .sold: return "Vendidos"
        case .reserved: return "Reservados"
        }
    }
}

// MARK: - Ordenación

enum CarSortOption: String, CaseIterable, Identifiable {
    case relevance
    case priceAsc
    case priceDesc
    case monthlyAsc
    case monthlyDesc
    case kmAsc
    case kmDesc
    case yearDesc
    case yearAsc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relevance: return "Los anuncios más relevantes"
        case .priceAsc: return "Los precios al contado más bajos"
        case .priceDesc: return "Los precios al contado más altos"
        case .monthlyAsc: return "Las cuotas mensuales más bajas"
        case .monthlyDesc: return "Las cuotas mensuales más altas"
        case .kmAsc: return "Los de menos km"
        case .kmDesc: return "Los de más km"
        case .yearDesc: return "Los más nuevos"
        case .yearAsc: return "Los más antiguos"
        }
    }
}

// MARK: - Filtros

struct CarListFilters: Equatable {
    var bodyTypes: Set<String> = []
    var brands: Set<String> = []
    var fuelTypes: Set<String> = []
    var sellerKinds: Set<String> = []
    var dgtLabels: Set<String> = []
    var colors: Set<String> = []
    var locations: Set<String> = []

    var minPriceEUR: Double?
    var maxPriceEUR: Double?
    var minYear: Int?
    var maxYear: Int?
    var minKm: Int?
    var maxKm: Int?

    var electricOnly: Bool = false
    var onlineServicesOnly: Bool = false
    var equipmentQuery: String = ""

    var hasActiveFilters: Bool {
        !bodyTypes.isEmpty
            || !brands.isEmpty
            || !fuelTypes.isEmpty
            || !sellerKinds.isEmpty
            || !dgtLabels.isEmpty
            || !colors.isEmpty
            || !locations.isEmpty
            || minPriceEUR != nil
            || maxPriceEUR != nil
            || minYear != nil
            || maxYear != nil
            || minKm != nil
            || maxKm != nil
            || electricOnly
            || onlineServicesOnly
            || !equipmentQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
