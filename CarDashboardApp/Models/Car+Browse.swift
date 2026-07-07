import Foundation

extension Car {
    /// Marca para filtros (columna o primera palabra del nombre).
    var brandForFilter: String {
        if let b = brandName?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty { return b }
        let parts = name.split(separator: " ").map(String.init)
        return parts.first ?? name
    }

    var colorForFilter: String {
        if let c = exteriorColorLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty { return c }
        return color
    }

    var isElectricVehicle: Bool {
        guard let f = fuelType?.lowercased() else { return false }
        return f.contains("eléctrico") || f.contains("electrico") || f.contains("bev")
            || f.contains(" ev") || f == "ev" || f.contains("phev") || f.contains("enchufable")
    }

    func matchesBrowseSearch(_ raw: String) -> Bool {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        let tokens = q.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let hay = [
            name, model, plate, String(year),
            brandName ?? "", fuelType ?? "", bodyType ?? "", locationText ?? "",
            dgtLabel ?? "", transmission ?? "", equipmentSummary ?? "", exteriorColorLabel ?? "",
            color, sellerKind ?? "", sellerDisplayLine,
        ]
            .joined(separator: " ")
            .lowercased()
        return tokens.allSatisfy { hay.contains($0) }
    }

    private var sellerDisplayLine: String {
        guard let k = sellerKind else { return "" }
        if let r = sellerRating {
            return "\(k) \(r)"
        }
        return k
    }

    func matchesBrowseFilters(_ f: CarListFilters) -> Bool {
        if f.electricOnly, !isElectricVehicle { return false }

        if f.onlineServicesOnly, onlineListing != true { return false }

        if !f.brands.isEmpty {
            let mine = brandForFilter.lowercased()
            let set = Set(f.brands.map { $0.lowercased() })
            guard set.contains(mine) else { return false }
        }

        if !f.bodyTypes.isEmpty {
            let mine = (bodyType ?? "").lowercased()
            guard !mine.isEmpty, f.bodyTypes.map({ $0.lowercased() }).contains(mine) else { return false }
        }

        if !f.fuelTypes.isEmpty {
            let mine = (fuelType ?? "").lowercased()
            guard !mine.isEmpty, f.fuelTypes.map({ $0.lowercased() }).contains(mine) else { return false }
        }

        if !f.sellerKinds.isEmpty {
            let mine = (sellerKind ?? "").lowercased()
            guard !mine.isEmpty, f.sellerKinds.map({ $0.lowercased() }).contains(mine) else { return false }
        }

        if !f.dgtLabels.isEmpty {
            let mine = (dgtLabel ?? "").lowercased()
            guard !mine.isEmpty, f.dgtLabels.map({ $0.lowercased() }).contains(mine) else { return false }
        }

        if !f.colors.isEmpty {
            let mine = colorForFilter.lowercased()
            guard f.colors.map({ $0.lowercased() }).contains(mine) else { return false }
        }

        if !f.locations.isEmpty {
            let mine = (locationText ?? "").lowercased()
            guard !mine.isEmpty, f.locations.map({ $0.lowercased() }).contains(mine) else { return false }
        }

        if let minP = f.minPriceEUR {
            guard let p = listPriceEUR, p >= minP else { return false }
        }
        if let maxP = f.maxPriceEUR {
            guard let p = listPriceEUR, p <= maxP else { return false }
        }

        if let y0 = f.minYear, year < y0 { return false }
        if let y1 = f.maxYear, year > y1 { return false }

        if let k0 = f.minKm {
            guard let km = mileageKm, km >= k0 else { return false }
        }
        if let k1 = f.maxKm {
            guard let km = mileageKm, km <= k1 else { return false }
        }

        let eq = f.equipmentQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !eq.isEmpty {
            let blob = "\(equipmentSummary ?? "") \(name) \(model)".lowercased()
            guard blob.contains(eq) else { return false }
        }

        return true
    }

    /// Segmento Todos / Vendidos / Reservados en la pestaña Coches.
    func matchesBrowseSegment(_ segment: CarsInventorySegment) -> Bool {
        switch segment {
        case .all:
            return true
        case .sold:
            return isInventorySold
        case .reserved:
            return isInventoryReserved
        }
    }

    var isInventorySold: Bool {
        if isSold == true { return true }
        return Self.matchesExplicitSoldStatus(stockStatus)
    }

    var isInventoryReserved: Bool {
        if isInventorySold { return false }
        if isReservable == true { return true }
        return Self.matchesExplicitReservedStatus(stockStatus)
    }

    static func matchesExplicitSoldStatus(_ raw: String?) -> Bool {
        let s = normalizedInventoryStatus(raw)
        guard !s.isEmpty else { return false }
        return explicitSoldStatuses.contains(s)
    }

    static func matchesExplicitReservedStatus(_ raw: String?) -> Bool {
        let s = normalizedInventoryStatus(raw)
        guard !s.isEmpty else { return false }
        return explicitReservedStatuses.contains(s)
    }

    private static let explicitSoldStatuses: Set<String> = [
        "vendido", "vendida", "sold", "sold_out", "sold-out", "sold out", "venta_cerrada", "soldout",
    ]

    private static let explicitReservedStatuses: Set<String> = [
        "reservado", "reservada", "reserved", "booking", "on_hold", "on hold", "hold",
    ]

    private static func normalizedInventoryStatus(_ raw: String?) -> String {
        (raw ?? "")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private var normalizedStockStatus: String {
        Self.normalizedInventoryStatus(stockStatus)
    }
}
