import Foundation

enum RemoteAssets {
    /// Foto del showroom (coches, fondo oscuro). Debe coincidir con la web CarHub365.
    /// URL: https://www.carhub365.es/images/car-dark-showroom.jpg
    static let carShowroomImageURL = URL(string: "https://www.carhub365.es/images/car-dark-showroom.jpg")!

    /// Fondos hero del dashboard (semillas fijas para caché estable).
    static var dashboardHeroStock: URL { carShowroomImageURL }
    static let dashboardHeroValue = URL(string: "https://picsum.photos/seed/carhub_value/800/640")!
    static let dashboardHeroCaptured = URL(string: "https://picsum.photos/seed/carhub_capture/800/640")!
    static let dashboardHeroCommission = URL(string: "https://picsum.photos/seed/carhub_comm/800/640")!

    /// Miniatura circular estable por hilo (listado tipo marketplace).
    static func chatListingCarPhoto(seed: Int) -> URL {
        URL(string: "https://picsum.photos/seed/dealcar\(seed)/400/400")!
    }
}
