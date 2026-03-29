import Foundation
import SwiftUI

@MainActor
final class CarsViewModel: ObservableObject {
    @Published var cars: [Car] = []
    @Published var selectedCarId: UUID?
    @Published var isLoadingVehicles = false
    @Published var vehiclesError: String?

    /// Listado tipo marketplace (pestaña Coches): búsqueda, orden y filtros sobre `cars` ya cargados.
    @Published var browseSearchText = ""
    @Published var browseSort: CarSortOption = .relevance
    @Published var browseFilters = CarListFilters()

    init() {}

    var selectedCar: Car? {
        cars.first { $0.id == selectedCarId }
    }

    func loadVehicles() async {
        isLoadingVehicles = true
        vehiclesError = nil
        defer { isLoadingVehicles = false }

        do {
            let rows = try await VehiclesService.fetchAll()
            cars = rows.enumerated().map { idx, row in row.toCar(index: idx) }
            if selectedCarId == nil || cars.first(where: { $0.id == selectedCarId }) == nil {
                selectedCarId = cars.first?.id
            }
        } catch {
            vehiclesError = error.localizedDescription
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

    private static func sortBrowsePairs(_ pairs: [(idx: Int, car: Car)], by option: CarSortOption) -> [Car] {
        switch option {
        case .relevance:
            return pairs.sorted { $0.idx < $1.idx }.map(\.car)

        case .priceAsc:
            return pairs.sorted { a, b in
                let ka = a.car.listPriceEUR ?? .infinity
                let kb = b.car.listPriceEUR ?? .infinity
                if ka != kb { return ka < kb }
                return a.idx < b.idx
            }.map(\.car)

        case .priceDesc:
            return pairs.sorted { a, b in
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
                let ka = a.car.monthlyPaymentEUR ?? .infinity
                let kb = b.car.monthlyPaymentEUR ?? .infinity
                if ka != kb { return ka < kb }
                return a.idx < b.idx
            }.map(\.car)

        case .monthlyDesc:
            return pairs.sorted { a, b in
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
                let ka = a.car.mileageKm.map(Double.init) ?? .infinity
                let kb = b.car.mileageKm.map(Double.init) ?? .infinity
                if ka != kb { return ka < kb }
                return a.idx < b.idx
            }.map(\.car)

        case .kmDesc:
            return pairs.sorted { a, b in
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
                if a.car.year != b.car.year { return a.car.year > b.car.year }
                return a.idx < b.idx
            }.map(\.car)

        case .yearAsc:
            return pairs.sorted { a, b in
                if a.car.year != b.car.year { return a.car.year < b.car.year }
                return a.idx < b.idx
            }.map(\.car)
        }
    }
}
