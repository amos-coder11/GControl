import Foundation

struct Car: Identifiable, Hashable {
    let id: UUID
    var name: String
    var model: String
    var plate: String
    var year: Int
    var icon: String
    var isConnected: Bool
    var color: String

    init(
        id: UUID = UUID(),
        name: String,
        model: String,
        plate: String,
        year: Int,
        icon: String = "car.fill",
        isConnected: Bool = false,
        color: String = "cyan"
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.plate = plate
        self.year = year
        self.icon = icon
        self.isConnected = isConnected
        self.color = color
    }
}
