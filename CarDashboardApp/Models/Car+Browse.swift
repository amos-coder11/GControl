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
}
