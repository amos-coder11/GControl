import Foundation
import SwiftUI

@MainActor
final class CarsViewModel: ObservableObject {
    @Published var cars: [Car] = MockData.cars
    @Published var selectedCarId: UUID?

    init() {
        selectedCarId = cars.first?.id
    }

    var selectedCar: Car? {
        cars.first { $0.id == selectedCarId }
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
