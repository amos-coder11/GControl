import Foundation

enum RemoteAssets {
    /// Foto del showroom (coches, fondo oscuro). Debe coincidir con la web CarHub365.
    /// URL: https://www.carhub365.es/images/car-dark-showroom.jpg
    static let carShowroomImageURL = URL(string: "https://www.carhub365.es/images/car-dark-showroom.jpg")!

    /// Miniatura circular estable por hilo (listado tipo marketplace).
    static func chatListingCarPhoto(seed: Int) -> URL {
        URL(string: "https://picsum.photos/seed/dealcar\(seed)/400/400")!
    }
}
