import SwiftUI

/// Red de origen del lead (insignia sobre el avatar con foto de coche).
enum ChatSocialPlatform: Hashable {
    case instagram
    case whatsApp
    case cochesNet
    case autoScout24
    case wallapop
    case facebook
}

/// Hilo de chat (lista + navegación a conversación).
struct ChatThread: Identifiable, Hashable {
    let id: UUID
    let title: String
    let preview: String
    let time: String
    let unread: Int?
    let avatarInitial: String?
    let avatarIcon: String?
    let avatarR: Double
    let avatarG: Double
    let avatarB: Double
    /// Foto del anuncio (circular en lista); si es nil se usa inicial / SF Symbol.
    let avatarCarURL: URL?
    /// Red de procedencia del lead (insignia sobre la foto).
    let socialSource: ChatSocialPlatform?
    let isVerified: Bool
    let isPinned: Bool

    enum ReadReceipt: Hashable {
        case none
        case sent
        case read
    }

    let readReceipt: ReadReceipt
    let showOpenButton: Bool

    var avatarColor: Color {
        Color(red: avatarR, green: avatarG, blue: avatarB)
    }

    static let samples: [ChatThread] = [
        ChatThread(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            title: "Taller central",
            preview: "El vehículo está listo para recogida.",
            time: "9:42",
            unread: 2,
            avatarInitial: nil,
            avatarIcon: nil,
            avatarR: 0.2, avatarG: 0.55, avatarB: 0.95,
            avatarCarURL: RemoteAssets.chatListingCarPhoto(seed: 1),
            socialSource: .instagram,
            isVerified: false,
            isPinned: true,
            readReceipt: .none,
            showOpenButton: false
        ),
        ChatThread(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
            title: "María · Ventas",
            preview: "Te envío el informe de comisiones del mes.",
            time: "Ayer",
            unread: nil,
            avatarInitial: nil,
            avatarIcon: nil,
            avatarR: 0.95, avatarG: 0.35, avatarB: 0.55,
            avatarCarURL: RemoteAssets.chatListingCarPhoto(seed: 2),
            socialSource: .whatsApp,
            isVerified: false,
            isPinned: false,
            readReceipt: .read,
            showOpenButton: false
        ),
        ChatThread(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
            title: "Cliente García",
            preview: "¿Podemos ver el coche el jueves por la tarde?",
            time: "sáb",
            unread: nil,
            avatarInitial: nil,
            avatarIcon: nil,
            avatarR: 0.95, avatarG: 0.62, avatarB: 0.18,
            avatarCarURL: RemoteAssets.chatListingCarPhoto(seed: 3),
            socialSource: .cochesNet,
            isVerified: false,
            isPinned: false,
            readReceipt: .sent,
            showOpenButton: false
        ),
        ChatThread(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
            title: "Soporte DealCar",
            preview: "Incidencia resuelta en el panel de concesionario.",
            time: "18/03",
            unread: 1,
            avatarInitial: nil,
            avatarIcon: "bubble.left.and.bubble.right.fill",
            avatarR: 0.35, avatarG: 0.78, avatarB: 0.62,
            avatarCarURL: nil,
            socialSource: nil,
            isVerified: true,
            isPinned: false,
            readReceipt: .none,
            showOpenButton: false
        ),
        ChatThread(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!,
            title: "DealCar Bot",
            preview: "/start — Asistente de inventario y citas.",
            time: "15/03",
            unread: nil,
            avatarInitial: nil,
            avatarIcon: "cpu.fill",
            avatarR: 0.45, avatarG: 0.45, avatarB: 0.5,
            avatarCarURL: nil,
            socialSource: nil,
            isVerified: true,
            isPinned: false,
            readReceipt: .none,
            showOpenButton: true
        ),
        ChatThread(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000006")!,
            title: "Financiación 🇺🇸",
            preview: "const dealerId = process.env.DEALCAR_DEALER_ID ?? \"b7c179e3…\"",
            time: "4:23",
            unread: nil,
            avatarInitial: nil,
            avatarIcon: nil,
            avatarR: 0.25, avatarG: 0.45, avatarB: 0.85,
            avatarCarURL: RemoteAssets.chatListingCarPhoto(seed: 6),
            socialSource: .autoScout24,
            isVerified: false,
            isPinned: false,
            readReceipt: .read,
            showOpenButton: false
        ),
        ChatThread(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000007")!,
            title: "Wallapop · BMW 320d",
            preview: "¿Sigue disponible? Puedo pasar mañana.",
            time: "mar",
            unread: 3,
            avatarInitial: nil,
            avatarIcon: nil,
            avatarR: 0.5, avatarG: 0.5, avatarB: 0.52,
            avatarCarURL: RemoteAssets.chatListingCarPhoto(seed: 7),
            socialSource: .wallapop,
            isVerified: false,
            isPinned: false,
            readReceipt: .sent,
            showOpenButton: false
        ),
        ChatThread(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000008")!,
            title: "Marketplace · Audi A4",
            preview: "Te dejo el enlace al informe CARFAX.",
            time: "lun",
            unread: nil,
            avatarInitial: nil,
            avatarIcon: nil,
            avatarR: 0.55, avatarG: 0.6, avatarB: 0.65,
            avatarCarURL: RemoteAssets.chatListingCarPhoto(seed: 8),
            socialSource: .facebook,
            isVerified: false,
            isPinned: false,
            readReceipt: .read,
            showOpenButton: false
        )
    ]
}
