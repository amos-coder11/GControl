import Foundation
import SwiftUI

enum DealershipPeriodScope: String, CaseIterable, Identifiable {
    case month = "Mes"
    case quarter = "Trimestre"
    case year = "Año"

    var id: String { rawValue }
}

@MainActor
final class DealershipStatsViewModel: ObservableObject {
    @Published var periodScope: DealershipPeriodScope = .month
    /// Etiqueta visible del período (ej. mes y año).
    @Published var periodDisplayLabel: String = ""

    @Published var vehiclesInStock: Int = 0
    @Published var vehiclesStockBadge: String = ""
    @Published var totalStockValue: String = "0€"
    @Published var totalStockBadge: String = ""
    @Published var carsSold: Int = 42
    @Published var salesProfit: String = "128.400 €"
    @Published var capturedCars: Int = 0
    @Published var capturedChangePercent: Int = 7
    @Published var commercialCommissions: String = "300€"
    @Published var commissionsSubtitle: String = "+100€ captación + 100€ venta agregado a vendedor"
    @Published var totalDealershipEarnings: String = "4100 €"
    @Published var totalEarningsSubtitle: String = "Beneficio ventas + beneficios agregados"

    init() {
        periodDisplayLabel = Self.monthLabel(for: Date())
    }

    func refreshFromInventory(cars: [Car], asOf date: Date = Date()) {
        periodDisplayLabel = Self.monthLabel(for: date)
        vehiclesInStock = cars.count

        let total = cars.reduce(0.0) { acc, car in
            acc + (car.listPriceEUR ?? 0)
        }
        totalStockValue = Self.formatEUR(total)
    }

    private static func monthLabel(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "LLLL yyyy"
        let raw = f.string(from: date)
        // Capitaliza el mes: "abril 2026" -> "Abril 2026"
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    private static func formatEUR(_ amount: Double) -> String {
        let n = NSNumber(value: amount.rounded())
        let f = NumberFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.groupingSeparator = "."
        f.decimalSeparator = ","
        let s = f.string(from: n) ?? "0"
        return "\(s)€"
    }
}
