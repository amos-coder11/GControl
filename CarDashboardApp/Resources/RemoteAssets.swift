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

    /// Fotos de coches reales (Unsplash) para avatares del listado de chat.
    enum ChatListingCarPhotos {
        static let volvoXC60 = URL(string: "https://images.unsplash.com/photo-1606664515524-ed2f786a0bd6?w=400&h=400&fit=crop")!
        static let audiRS6 = URL(string: "https://images.unsplash.com/photo-1603584173870-7f23fdae1b7a?w=400&h=400&fit=crop")!
        static let bmwSerie3 = URL(string: "https://images.unsplash.com/photo-1555215695-3004980ad54e?w=400&h=400&fit=crop")!
        static let cupraFormentor = URL(string: "https://images.unsplash.com/photo-1503376780353-7e6692767b70?w=400&h=400&fit=crop")!
        static let teslaModel3 = URL(string: "https://images.unsplash.com/photo-1560958089-b8a1929cea89?w=400&h=400&fit=crop")!
        static let fordMustang = URL(string: "https://images.unsplash.com/photo-1494976388531-d1058494cdd8?w=400&h=400&fit=crop")!
        static let bmw320d = URL(string: "https://images.unsplash.com/photo-1617814076367-b759c7d7e738?w=400&h=400&fit=crop")!
        static let audiA4 = URL(string: "https://images.unsplash.com/photo-1614200187524-dc4b892acf16?w=400&h=400&fit=crop")!
    }
}
