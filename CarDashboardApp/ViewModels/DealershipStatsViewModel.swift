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
    @Published var carsSold: Int = 0
    @Published var salesProfit: String = "0 €"
    @Published var capturedCars: Int = 0
    @Published var capturedChangePercent: Int = 0
    @Published var commercialCommissions: String = "0€"
    @Published var commissionsSubtitle: String = "Comisiones del equipo"
    @Published var totalDealershipEarnings: String = "0 €"
    @Published var totalEarningsSubtitle: String = "Importe total de ventas del equipo"

    // ─── Métricas REALES de leads (del CRM) ───
    @Published var leadsTotal: Int = 0
    @Published var leadOpportunities: Int = 0
    @Published var appointmentsCount: Int = 0
    @Published var conversionRate: String = "0%"
    @Published var avgResponseLabel: String = "—"
    @Published var isLoadingMetrics: Bool = false

    init() {
        periodDisplayLabel = Self.monthLabel(for: Date())
    }

    /// Carga las métricas reales del backend (leads + ranking de comerciales).
    func refreshFromBackend(token: String) async {
        isLoadingMetrics = true
        defer { isLoadingMetrics = false }
        if let m = try? await CrmMetricsService.leadMetrics(token: token) {
            leadsTotal = m.total
            leadOpportunities = m.opportunities
            appointmentsCount = m.appointments
            carsSold = m.won
            capturedCars = m.captacion
            conversionRate = String(format: "%.0f%%", m.wonRate)
            if let s = m.avgResponseSeconds {
                avgResponseLabel = s >= 60 ? "\(s / 60) min" : "\(s) s"
            }
        }
        if let rows = try? await CrmMetricsService.commercialRanking(token: token), !rows.isEmpty {
            let totalImporte = rows.reduce(0.0) { $0 + $1.importe }
            if totalImporte > 0 {
                totalDealershipEarnings = Self.formatEUR(totalImporte)
                salesProfit = Self.formatEUR(totalImporte)
            }
        }
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

// MARK: - Servicio de métricas (movido aquí para que el target de Xcode lo compile)

/// Cliente para las MÉTRICAS reales del CRM (carhubackend): estadísticas de
/// leads y ranking de comerciales. Autenticado con el token de la sesión de
/// Supabase del usuario (igual que el chat).
enum CrmMetricsService {
    static let baseURL = URL(string: "https://carhubackend.onrender.com")!

    enum ServiceError: Error { case badResponse }

    // MARK: Modelos

    struct LeadMetrics {
        let total: Int
        let byStage: [String: Int]
        let appointments: Int
        let wonRate: Double      // % de leads ganados
        let lostRate: Double     // % de leads perdidos
        let appointmentRate: Double
        let avgResponseSeconds: Int?

        var won: Int { byStage["ganado"] ?? 0 }
        var lost: Int { byStage["perdido"] ?? 0 }
        var opportunities: Int { byStage["oportunidad"] ?? 0 }
        var captacion: Int { byStage["captacion"] ?? 0 }
    }

    struct CommercialRow: Identifiable {
        let id: String
        let name: String
        let role: String
        let avatar: String?
        let ventas: Int
        let captaciones: Int
        let importe: Double
        let conversion: String
    }

    // MARK: Peticiones

    static func leadMetrics(token: String) async throws -> LeadMetrics? {
        let json = try await getJSON(path: "/api/leads/metrics", token: token)
        guard let m = json["metrics"] as? [String: Any] else { return nil }
        var stages: [String: Int] = [:]
        if let bs = m["byStage"] as? [String: Any] {
            for (k, v) in bs { stages[k.lowercased()] = intOf(v) ?? 0 }
        }
        return LeadMetrics(
            total: intOf(m["total"]) ?? 0,
            byStage: stages,
            appointments: intOf(m["appointments"]) ?? 0,
            wonRate: doubleOf(m["wonRate"]) ?? 0,
            lostRate: doubleOf(m["lostRate"]) ?? 0,
            appointmentRate: doubleOf(m["appointmentRate"]) ?? 0,
            avgResponseSeconds: intOf(m["avgResponseSeconds"])
        )
    }

    static func commercialRanking(token: String) async throws -> [CommercialRow] {
        let json = try await getJSON(path: "/api/commercial-ranking", token: token)
        let rows = (json["ranking"] as? [[String: Any]]) ?? []
        return rows.map { r in
            CommercialRow(
                id: flexString(r["user_id"]) ?? flexString(r["id"]) ?? UUID().uuidString,
                name: (r["name"] as? String) ?? "Comercial",
                role: (r["role"] as? String) ?? "user",
                avatar: r["avatar"] as? String,
                ventas: intOf(r["ventas"]) ?? 0,
                captaciones: intOf(r["captaciones"]) ?? 0,
                importe: doubleOf(r["importe"]) ?? 0,
                conversion: (r["conversion"] as? String) ?? "0%"
            )
        }
    }

    // MARK: Utilidades

    private static func getJSON(path: String, token: String) async throws -> [String: Any] {
        guard let url = URL(string: baseURL.absoluteString + path) else { throw ServiceError.badResponse }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse, (200 ... 299).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ServiceError.badResponse }
        return json
    }

    private static func intOf(_ v: Any?) -> Int? {
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(Double(s) ?? 0) }
        return nil
    }
    private static func doubleOf(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }
    private static func flexString(_ v: Any?) -> String? {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }
}
