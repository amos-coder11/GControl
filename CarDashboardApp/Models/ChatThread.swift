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

/// Tipo de hilo: leads comerciales vs chat interno del equipo.
enum ChatThreadKind: Hashable {
    case lead
    case teamGroup
    case teamDirect
}

/// Hilo de chat (lista + navegación a conversación).
struct ChatThread: Identifiable, Hashable {
    /// Id fijo del grupo «Mi equipo» (misma conversación al reabrir).
    static let teamGroupThreadId = UUID(uuidString: "E1B0D401-0000-4000-8000-0000000000FE")!

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
    /// Origen del hilo (por defecto lead de muestra).
    let kind: ChatThreadKind
    /// Para `teamDirect`, mismo valor que `id` (usuario con el que chateas).
    let peerUserId: UUID?

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

    /// Vista previa en lista cuando el coordinador IA envía algo a ese compañero.
    func withCoordinatorOutboundPreview(_ line: String) -> ChatThread {
        ChatThread(
            id: id,
            title: title,
            preview: "IA · \(line)",
            time: "Ahora",
            unread: unread,
            avatarInitial: avatarInitial,
            avatarIcon: avatarIcon,
            avatarR: avatarR,
            avatarG: avatarG,
            avatarB: avatarB,
            avatarCarURL: avatarCarURL,
            socialSource: socialSource,
            isVerified: isVerified,
            isPinned: isPinned,
            kind: kind,
            peerUserId: peerUserId,
            readReceipt: readReceipt,
            showOpenButton: showOpenButton
        )
    }

    /// Grupo con todo el directorio (misma UI que el resto de chats).
    static func makeTeamGroup(memberCount: Int) -> ChatThread {
        let preview: String
        switch memberCount {
        case 0: preview = "Sin personas en el directorio"
        case 1: preview = "1 persona en el directorio"
        default: preview = "\(memberCount) personas en el directorio"
        }
        return ChatThread(
            id: teamGroupThreadId,
            title: "Mi equipo · grupo",
            preview: preview,
            time: "Ahora",
            unread: nil,
            avatarInitial: nil,
            avatarIcon: "person.3.fill",
            avatarR: 0.22, avatarG: 0.62, avatarB: 0.92,
            avatarCarURL: nil,
            socialSource: nil,
            isVerified: false,
            isPinned: false,
            kind: .teamGroup,
            peerUserId: nil,
            readReceipt: .none,
            showOpenButton: false
        )
    }

    /// DM interno: `id` estable = `userId` del compañero (sin colisión con UUIDs de muestra de leads).
    static func makeTeamDirect(from row: CommunityProfilesService.DirectoryRow) -> ChatThread {
        let name = row.resolvedDisplayName
        let initials: String = {
            let parts = name.split(separator: " ").filter { !$0.isEmpty }
            if parts.count >= 2, let a = parts[0].first, let b = parts[1].first {
                return "\(a)\(b)".uppercased()
            }
            if let f = name.first { return String(f).uppercased() }
            return "?"
        }()
        return ChatThread(
            id: row.userId,
            title: name,
            preview: "Mensaje privado con el equipo",
            time: "Ahora",
            unread: nil,
            avatarInitial: initials,
            avatarIcon: nil,
            avatarR: 0.28, avatarG: 0.48, avatarB: 0.88,
            avatarCarURL: nil,
            socialSource: nil,
            isVerified: false,
            isPinned: false,
            kind: .teamDirect,
            peerUserId: row.userId,
            readReceipt: .read,
            showOpenButton: false
        )
    }

    static let samples: [ChatThread] = [
        ChatThread(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            title: "Instagram · Volvo XC60",
            preview: "El Volvo está listo para entrega en el concesionario.",
            time: "9:42",
            unread: 2,
            avatarInitial: nil,
            avatarIcon: nil,
            avatarR: 0.2, avatarG: 0.55, avatarB: 0.95,
            avatarCarURL: RemoteAssets.ChatListingCarPhotos.volvoXC60,
            socialSource: .instagram,
            isVerified: false,
            isPinned: true,
            kind: .lead,
            peerUserId: nil,
            readReceipt: .none,
            showOpenButton: false
        ),
        ChatThread(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
            title: "WhatsApp · Audi RS6",
            preview: "¿Sigues con el RS6 publicado? Me interesa financiación.",
            time: "Ayer",
            unread: nil,
            avatarInitial: nil,
            avatarIcon: nil,
            avatarR: 0.95, avatarG: 0.35, avatarB: 0.55,
            avatarCarURL: RemoteAssets.ChatListingCarPhotos.audiRS6,
            socialSource: .whatsApp,
            isVerified: false,
            isPinned: false,
            kind: .lead,
            peerUserId: nil,
            readReceipt: .read,
            showOpenButton: false
        ),
        ChatThread(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
            title: "Coches.net · BMW Serie 3",
            preview: "¿Podemos ver el Serie 3 el jueves por la tarde?",
            time: "sáb",
            unread: nil,
            avatarInitial: nil,
            avatarIcon: nil,
            avatarR: 0.95, avatarG: 0.62, avatarB: 0.18,
            avatarCarURL: RemoteAssets.ChatListingCarPhotos.bmwSerie3,
            socialSource: .cochesNet,
            isVerified: false,
            isPinned: false,
            kind: .lead,
            peerUserId: nil,
            readReceipt: .sent,
            showOpenButton: false
        ),
        ChatThread(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
            title: "DealCar · Cupra Formentor",
            preview: "Incidencia resuelta: ya ves el Formentor en el panel.",
            time: "18/03",
            unread: 1,
            avatarInitial: nil,
            avatarIcon: nil,
            avatarR: 0.35, avatarG: 0.78, avatarB: 0.62,
            avatarCarURL: RemoteAssets.ChatListingCarPhotos.cupraFormentor,
            socialSource: nil,
            isVerified: true,
            isPinned: false,
            kind: .lead,
            peerUserId: nil,
            readReceipt: .none,
            showOpenButton: false
        ),
        ChatThread(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!,
            title: "DealCar Bot · Tesla Model 3",
            preview: "/start — Asistente de inventario y citas.",
            time: "15/03",
            unread: nil,
            avatarInitial: nil,
            avatarIcon: nil,
            avatarR: 0.45, avatarG: 0.45, avatarB: 0.5,
            avatarCarURL: RemoteAssets.ChatListingCarPhotos.teslaModel3,
            socialSource: nil,
            isVerified: true,
            isPinned: false,
            kind: .lead,
            peerUserId: nil,
            readReceipt: .none,
            showOpenButton: true
        ),
        ChatThread(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000006")!,
            title: "AutoScout24 · Ford Mustang",
            preview: "const dealerId = process.env.DEALCAR_DEALER_ID ?? \"b7c179e3…\"",
            time: "4:23",
            unread: nil,
            avatarInitial: nil,
            avatarIcon: nil,
            avatarR: 0.25, avatarG: 0.45, avatarB: 0.85,
            avatarCarURL: RemoteAssets.ChatListingCarPhotos.fordMustang,
            socialSource: .autoScout24,
            isVerified: false,
            isPinned: false,
            kind: .lead,
            peerUserId: nil,
            readReceipt: .read,
            showOpenButton: false
        ),
        ChatThread(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000007")!,
            title: "Wallapop · BMW 320d",
            preview: "¿Sigue disponible el 320d? Puedo pasar mañana.",
            time: "mar",
            unread: 3,
            avatarInitial: nil,
            avatarIcon: nil,
            avatarR: 0.5, avatarG: 0.5, avatarB: 0.52,
            avatarCarURL: RemoteAssets.ChatListingCarPhotos.bmw320d,
            socialSource: .wallapop,
            isVerified: false,
            isPinned: false,
            kind: .lead,
            peerUserId: nil,
            readReceipt: .sent,
            showOpenButton: false
        ),
        ChatThread(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000008")!,
            title: "Marketplace · Audi A4",
            preview: "Te dejo el enlace al informe CARFAX del A4.",
            time: "lun",
            unread: nil,
            avatarInitial: nil,
            avatarIcon: nil,
            avatarR: 0.55, avatarG: 0.6, avatarB: 0.65,
            avatarCarURL: RemoteAssets.ChatListingCarPhotos.audiA4,
            socialSource: .facebook,
            isVerified: false,
            isPinned: false,
            kind: .lead,
            peerUserId: nil,
            readReceipt: .read,
            showOpenButton: false
        )
    ]
}
