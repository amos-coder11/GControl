import Foundation
import SwiftUI

enum MockData {
    static let cars: [Car] = [
        Car(
            name: "Mi BMW",
            model: "M4 Competition",
            plate: "4523 GHK",
            year: 2024,
            icon: "car.fill",
            isConnected: true,
            color: "cyan"
        ),
        Car(
            name: "Audi familiar",
            model: "RS6 Avant",
            plate: "7891 BCD",
            year: 2023,
            icon: "suv.side.fill",
            isConnected: false,
            color: "orange"
        ),
        Car(
            name: "Porsche fin de semana",
            model: "911 Carrera S",
            plate: "1234 XYZ",
            year: 2025,
            icon: "car.side.fill",
            isConnected: false,
            color: "mint"
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
