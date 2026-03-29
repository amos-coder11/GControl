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
    @Published var periodDisplayLabel: String = "Marzo 2026"

    @Published var vehiclesInStock: Int = 271
    @Published var vehiclesStockBadge: String = "• 0%"
    @Published var totalStockValue: String = "12.918.881€"
    @Published var totalStockBadge: String = "• 0%"
    @Published var carsSold: Int = 42
    @Published var salesProfit: String = "128.400 €"
    @Published var capturedCars: Int = 0
    @Published var capturedChangePercent: Int = 7
    @Published var commercialCommissions: String = "300€"
    @Published var commissionsSubtitle: String = "+100€ captación + 100€ venta agregado a vendedor"
    @Published var totalDealershipEarnings: String = "4100 €"
    @Published var totalEarningsSubtitle: String = "Beneficio ventas + beneficios agregados"
}
