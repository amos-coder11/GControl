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

    /// Listado tipo marketplace (pestaña Coches): búsqueda, orden y filtros sobre `cars` ya cargados.
    @Published var browseSearchText = ""
    @Published var browseSort: CarSortOption = .relevance
    @Published var browseFilters = CarListFilters()

    private let pageSize = 50

    init() {}

    var selectedCar: Car? {
        cars.first { $0.id == selectedCarId }
    }

    /// Carga progresiva: primera página rápido, luego el resto en background.
    func loadVehicles() async {
        isLoadingVehicles = true
        vehiclesError = nil
        hasMorePages = true

        do {
            // Primera página — se muestra inmediatamente en la UI
            let firstPage = try await VehiclesService.fetchPage(offset: 0, limit: pageSize)
            try Task.checkCancellation()
            cars = firstPage.enumerated().map { idx, row in row.toCar(index: idx) }
            isLoadingVehicles = false

            if selectedCarId == nil || cars.first(where: { $0.id == selectedCarId }) == nil {
                selectedCarId = cars.first?.id
            }

            // Si la primera página está completa, cargar el resto en background
            guard firstPage.count >= pageSize else {
                hasMorePages = false
                return
            }

            isLoadingMoreVehicles = true
            var offset = pageSize
            while true {
                try Task.checkCancellation()
                let page = try await VehiclesService.fetchPage(offset: offset, limit: pageSize)
                try Task.checkCancellation()

                if page.isEmpty {
                    hasMorePages = false
                    break
                }

                let baseIdx = cars.count
                let newCars = page.enumerated().map { idx, row in row.toCar(index: baseIdx + idx) }
                cars.append(contentsOf: newCars)

                if page.count < pageSize {
                    hasMorePages = false
                    break
                }
                offset += pageSize
            }
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
            $0.car.matchesBrowseSearch(browseSearchText) && $0.car.matchesBrowseFilters(browseFilters)
        }
        return Self.sortBrowsePairs(filtered, by: browseSort)
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
