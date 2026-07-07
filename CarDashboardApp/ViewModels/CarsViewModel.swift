import Foundation
import SwiftUI

@MainActor
final class CarsViewModel: ObservableObject {
    @Published var cars: [Car] = []
    @Published var selectedCarId: UUID?
    @Published var isLoadingVehicles = false
    @Published var isLoadingMoreVehicles = false
    @Published var vehiclesError: String?
    @Published var hasMorePages = true
    /// Última carga terminó sin filas en servidor (útil para mensajes cuando no hay filtros activos).
    @Published private(set) var lastFetchHadZeroRowsFromBackend = false

    /// Listado tipo marketplace (pestaña Coches): búsqueda, orden y segmento sobre `cars` ya cargados.
    @Published var browseSearchText = ""
    /// Por defecto: precio al contado más alto primero al abrir la app.
    @Published var browseSort: CarSortOption = .priceDesc
    @Published var browseSegment: CarsInventorySegment = .all

    init() {}

    var selectedCar: Car? {
        cars.first { $0.id == selectedCarId }
    }

    /// Carga progresiva: primera página rápido, luego el resto en background.
    /// Si se pasa `companyId`, solo trae vehículos de esa empresa (+ catálogo público sin empresa).
    func loadVehicles(companyId: UUID? = nil) async {
        isLoadingVehicles = true
        vehiclesError = nil
        hasMorePages = true
        lastFetchHadZeroRowsFromBackend = false

        do {
            try Task.checkCancellation()
            let rows = try await VehiclesService.fetchAllMergedForMarketplace(companyId: companyId) { partial in
                await MainActor.run {
                    self.applyLoadedVehicleRows(partial)
                    self.isLoadingVehicles = false
                }
            }
            try Task.checkCancellation()
            applyLoadedVehicleRows(rows)
            hasMorePages = false
            isLoadingVehicles = false
            isLoadingMoreVehicles = false

        } catch is CancellationError {
            // La tarea fue cancelada (ej. al navegar fuera) — no mostrar error al usuario
            isLoadingVehicles = false
            isLoadingMoreVehicles = false
        } catch {
            vehiclesError = error.localizedDescription
            isLoadingVehicles = false
            isLoadingMoreVehicles = false
        }
    }

    private func applyLoadedVehicleRows(_ rows: [VehicleRow]) {
        lastFetchHadZeroRowsFromBackend = rows.isEmpty
        cars = rows.enumerated().map { idx, row in row.toCar(index: idx) }
        if selectedCarId == nil || cars.first(where: { $0.id == selectedCarId }) == nil {
            selectedCarId = cars.first?.id
        }
    }

    func selectCar(_ car: Car) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            selectedCarId = car.id
        }
    }

    func isSelected(_ car: Car) -> Bool {
        car.id == selectedCarId
    }

    func displayedBrowseCars() -> [Car] {
        typealias Pair = (idx: Int, car: Car)
        let pairs: [Pair] = cars.enumerated().map { (idx: $0.offset, car: $0.element) }
        let filtered = pairs.filter {
            $0.car.matchesBrowseSearch(browseSearchText)
                && $0.car.matchesBrowseSegment(browseSegment)
        }
        let sorted = Self.sortBrowsePairs(filtered, by: browseSort)
        return Self.moveBrowseListPinnedToEnd(sorted)
    }

    func soldInventoryCount() -> Int {
        cars.filter { $0.matchesBrowseSegment(.sold) }.count
    }

    func reservedInventoryCount() -> Int {
        cars.filter { $0.matchesBrowseSegment(.reserved) }.count
    }

    /// Anuncio concreto que debe mostrarse siempre al final; el resto conserva el orden del criterio elegido.
    private static func pinsToEndOfBrowseList(_ car: Car) -> Bool {
        let brand = (car.brandName ?? "").lowercased()
        let title = car.name.lowercased()
        let model = car.model.lowercased()
        let lambo = brand.contains("lamborghini") || title.contains("lamborghini")
        let aventador = model.contains("aventador") || title.contains("aventador")
        guard lambo && aventador else { return false }
        guard let p = car.listPriceEUR, abs(p - 230_000) < 1 else { return false }
        let trans = car.transmission?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trans == "ISR" else { return false }
        return true
    }

    private static func moveBrowseListPinnedToEnd(_ ordered: [Car]) -> [Car] {
        let head = ordered.filter { !pinsToEndOfBrowseList($0) }
        let tail = ordered.filter { pinsToEndOfBrowseList($0) }
        return head + tail
    }

    /// Coches con al menos una imagen resoluble (URL, storage, base64 o galería) van primero en el listado.
    private static func hasBrowseImage(_ car: Car) -> Bool {
        !car.resolvedImageSlots.isEmpty
    }

    private static func sortBrowsePairs(_ pairs: [(idx: Int, car: Car)], by option: CarSortOption) -> [Car] {
        switch option {
        case .relevance:
            return pairs.sorted { a, b in
                let ha = Self.hasBrowseImage(a.car)
                let hb = Self.hasBrowseImage(b.car)
                if ha != hb { return ha }
                return a.idx < b.idx
            }.map(\.car)

        case .priceAsc:
            return pairs.sorted { a, b in
                let ha = Self.hasBrowseImage(a.car)
                let hb = Self.hasBrowseImage(b.car)
                if ha != hb { return ha }
                let ka = a.car.listPriceEUR ?? .infinity
                let kb = b.car.listPriceEUR ?? .infinity
                if ka != kb { return ka < kb }
                return a.idx < b.idx
            }.map(\.car)

        case .priceDesc:
            return pairs.sorted { a, b in
                let ha = Self.hasBrowseImage(a.car)
                let hb = Self.hasBrowseImage(b.car)
                if ha != hb { return ha }
                switch (a.car.listPriceEUR, b.car.listPriceEUR) {
                case (nil, nil): return a.idx < b.idx
                case (nil, _): return false
                case (_, nil): return true
                case let (x?, y?):
                    if x != y { return x > y }
                    return a.idx < b.idx
                }
            }.map(\.car)

        case .monthlyAsc:
            return pairs.sorted { a, b in
                let ha = Self.hasBrowseImage(a.car)
                let hb = Self.hasBrowseImage(b.car)
                if ha != hb { return ha }
                let ka = a.car.monthlyPaymentEUR ?? .infinity
                let kb = b.car.monthlyPaymentEUR ?? .infinity
                if ka != kb { return ka < kb }
                return a.idx < b.idx
            }.map(\.car)

        case .monthlyDesc:
            return pairs.sorted { a, b in
                let ha = Self.hasBrowseImage(a.car)
                let hb = Self.hasBrowseImage(b.car)
                if ha != hb { return ha }
                switch (a.car.monthlyPaymentEUR, b.car.monthlyPaymentEUR) {
                case (nil, nil): return a.idx < b.idx
                case (nil, _): return false
                case (_, nil): return true
                case let (x?, y?):
                    if x != y { return x > y }
                    return a.idx < b.idx
                }
            }.map(\.car)

        case .kmAsc:
            return pairs.sorted { a, b in
                let ha = Self.hasBrowseImage(a.car)
                let hb = Self.hasBrowseImage(b.car)
                if ha != hb { return ha }
                let ka = a.car.mileageKm.map(Double.init) ?? .infinity
                let kb = b.car.mileageKm.map(Double.init) ?? .infinity
                if ka != kb { return ka < kb }
                return a.idx < b.idx
            }.map(\.car)

        case .kmDesc:
            return pairs.sorted { a, b in
                let ha = Self.hasBrowseImage(a.car)
                let hb = Self.hasBrowseImage(b.car)
                if ha != hb { return ha }
                switch (a.car.mileageKm, b.car.mileageKm) {
                case (nil, nil): return a.idx < b.idx
                case (nil, _): return false
                case (_, nil): return true
                case let (x?, y?):
                    if x != y { return x > y }
                    return a.idx < b.idx
                }
            }.map(\.car)

        case .yearDesc:
            return pairs.sorted { a, b in
                let ha = Self.hasBrowseImage(a.car)
                let hb = Self.hasBrowseImage(b.car)
                if ha != hb { return ha }
                if a.car.year != b.car.year { return a.car.year > b.car.year }
                return a.idx < b.idx
            }.map(\.car)

        case .yearAsc:
            return pairs.sorted { a, b in
                let ha = Self.hasBrowseImage(a.car)
                let hb = Self.hasBrowseImage(b.car)
                if ha != hb { return ha }
                if a.car.year != b.car.year { return a.car.year < b.car.year }
                return a.idx < b.idx
            }.map(\.car)
        }
    }
}
