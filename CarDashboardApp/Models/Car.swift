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
    /// URL absoluta lista para descargar (externa o ya resuelta).
    var imageURLString: String?
    /// Solo nombre de archivo con extensión de imagen → `storage.from("vehicles").getPublicURL`.
    var imagePublicVehiclesFileName: String?
    /// Clave dentro del bucket privado (p. ej. `{user_id}/{vehicle_id}/foto.jpg`).
    var imageSignedStoragePath: String?
    var imageSignedStorageBucket: String?
    /// Payload base64 (sin prefijo `data:image/...;base64,`).
    var imageBase64: String?

    init(
        id: UUID = UUID(),
        name: String,
        model: String,
        plate: String,
        year: Int,
        icon: String = "car.fill",
        isConnected: Bool = false,
        color: String = "cyan",
        imageURLString: String? = nil,
        imagePublicVehiclesFileName: String? = nil,
        imageSignedStoragePath: String? = nil,
        imageSignedStorageBucket: String? = nil,
        imageBase64: String? = nil
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.plate = plate
        self.year = year
        self.icon = icon
        self.isConnected = isConnected
        self.color = color
        self.imageURLString = imageURLString
        self.imagePublicVehiclesFileName = imagePublicVehiclesFileName
        self.imageSignedStoragePath = imageSignedStoragePath
        self.imageSignedStorageBucket = imageSignedStorageBucket
        self.imageBase64 = imageBase64
    }
}
