import Foundation
import SwiftUI

struct CarMetric: Identifiable {
    let id: UUID
    var label: String
    var value: Double
    var unit: String
    var icon: String
    var maxValue: Double
    var color: Color

    init(
        id: UUID = UUID(),
        label: String,
        value: Double,
        unit: String,
        icon: String,
        maxValue: Double,
        color: Color = .cyan
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.unit = unit
        self.icon = icon
        self.maxValue = maxValue
        self.color = color
    }

    var percentage: Double {
        guard maxValue > 0 else { return 0 }
        return min(value / maxValue, 1.0)
    }

    var formattedValue: String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}
