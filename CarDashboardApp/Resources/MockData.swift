import Foundation
import SwiftUI

/// Solo para **previews** de SwiftUI y ejemplos en `#Preview`; el listado real viene de Supabase (`CarsViewModel`).
enum MockData {
    private static func imageSlots(urls: [String]) -> [CarImageSlot] {
        urls.compactMap { CarImageSlot(classifyingRaw: $0) }
    }

    static let cars: [Car] = [
        Car(
            name: "VOLVO XC60 2.0 T6 AWD Recharge Plus",
            model: "XC60",
            plate: "4523 GHK",
            year: 2024,
            icon: "suv.side.fill",
            isConnected: true,
            color: "cyan",
            imageURLString: "https://images.unsplash.com/photo-1606664515524-ed2f786a0bd6?w=800",
            imageSlots: imageSlots(urls: [
                "https://images.unsplash.com/photo-1606664515524-ed2f786a0bd6?w=800",
                "https://images.unsplash.com/photo-1494976388531-d1058494cdd8?w=800",
                "https://images.unsplash.com/photo-1503376780353-7e6692767b70?w=800",
            ]),
            brandName: "Volvo",
            listPriceEUR: 59_700,
            financedPriceEUR: 57_700,
            monthlyPaymentEUR: 822.74,
            mileageKm: 6,
            fuelType: "Híbrido enchufable",
            bodyType: "SUV",
            locationText: "A Coruña",
            sellerKind: "Profesional",
            sellerRating: 4.6,
            dgtLabel: "ECO",
            powerCv: 350,
            transmission: "Automático",
            equipmentSummary: "Techo panorámico, LED Matrix, asientos calefactados",
            exteriorColorLabel: "Negro",
            onlineListing: true,
            isReservable: true
        ),
        Car(
            name: "Audi RS6 Avant performance",
            model: "RS6 Avant",
            plate: "7891 BCD",
            year: 2023,
            icon: "car.side.fill",
            isConnected: false,
            color: "orange",
            imageURLString: "https://images.unsplash.com/photo-1603584173870-7f23fdae1b7a?w=800",
            imageSlots: imageSlots(urls: [
                "https://images.unsplash.com/photo-1603584173870-7f23fdae1b7a?w=800",
                "https://images.unsplash.com/photo-1614200187524-dc4b892acf16?w=800",
                "https://images.unsplash.com/photo-1552519507-da3b142c6e3d?w=800",
            ]),
            brandName: "Audi",
            listPriceEUR: 124_900,
            monthlyPaymentEUR: 1_450,
            mileageKm: 18_500,
            fuelType: "Gasolina",
            bodyType: "Familiar",
            locationText: "Madrid",
            sellerKind: "Profesional",
            sellerRating: 4.8,
            dgtLabel: "C",
            powerCv: 630,
            transmission: "Automático",
            equipmentSummary: "Cerámica, Bang & Olufsen, asistencia en carretera",
            exteriorColorLabel: "Gris",
            onlineListing: true,
            isReservable: false
        ),
        Car(
            name: "Tesla Model 3 Long Range",
            model: "Model 3",
            plate: "1234 XYZ",
            year: 2025,
            icon: "bolt.car",
            isConnected: false,
            color: "mint",
            imageURLString: "https://images.unsplash.com/photo-1560958089-b8a1929cea89?w=800",
            imageSlots: imageSlots(urls: [
                "https://images.unsplash.com/photo-1560958089-b8a1929cea89?w=800",
                "https://images.unsplash.com/photo-1536700503339-1e4b06520771?w=800",
                "https://images.unsplash.com/photo-1617788138017-80ad40651399?w=800",
            ]),
            brandName: "Tesla",
            listPriceEUR: 42_990,
            monthlyPaymentEUR: 589,
            mileageKm: 120,
            fuelType: "Eléctrico",
            bodyType: "Berlina",
            locationText: "Barcelona",
            sellerKind: "Particular",
            sellerRating: 4.2,
            dgtLabel: "0 emisiones",
            powerCv: 351,
            transmission: "Automático",
            equipmentSummary: "Autopilot, techo de cristal, supercharger",
            exteriorColorLabel: "Blanco",
            onlineListing: false,
            isReservable: false
        )
    ]

    static func initialMetrics() -> [CarMetric] {
        [
            CarMetric(label: "Velocidad", value: 72, unit: "km/h", icon: "gauge.with.dots.needle.50percent", maxValue: 260, color: .cyan),
            CarMetric(label: "RPM", value: 2800, unit: "rpm", icon: "dial.medium.fill", maxValue: 8000, color: .orange),
            CarMetric(label: "Temperatura", value: 88, unit: "°C", icon: "thermometer.medium", maxValue: 130, color: .red),
            CarMetric(label: "Combustible", value: 68, unit: "%", icon: "fuelpump.fill", maxValue: 100, color: .green),
            CarMetric(label: "Batería", value: 92, unit: "%", icon: "battery.75percent", maxValue: 100, color: .yellow),
            CarMetric(label: "Turbo", value: 1.2, unit: "bar", icon: "wind", maxValue: 2.5, color: .purple)
        ]
    }
}
