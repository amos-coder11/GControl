import Foundation
import SwiftUI

@MainActor
final class CarsViewModel: ObservableObject {
    @Published var cars: [Car] = []
    @Published var selectedCarId: UUID?
    @Published var isLoadingVehicles = false
    @Published var vehiclesError: String?

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
}
