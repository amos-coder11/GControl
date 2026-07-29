import SwiftUI

/// Red de origen del lead (insignia sobre el avatar).
enum ChatSocialPlatform: Hashable {
    case instagram
    case whatsApp
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
    /// Última actividad (orden estilo WhatsApp en la bandeja).
    let lastActivityAt: Date?

    var avatarColor: Color {
        Color(red: avatarR, green: avatarG, blue: avatarB)
    }

    /// Actualiza la foto del avatar (p. ej. foto de perfil de WhatsApp del CRM).
    func withAvatarCarURL(_ url: URL?) -> ChatThread {
        ChatThread(
            id: id,
            title: title,
            preview: preview,
            time: time,
            unread: unread,
            avatarInitial: avatarInitial,
            avatarIcon: avatarIcon,
            avatarR: avatarR,
            avatarG: avatarG,
            avatarB: avatarB,
            avatarCarURL: url,
            socialSource: socialSource,
            isVerified: isVerified,
            isPinned: isPinned,
            kind: kind,
            peerUserId: peerUserId,
            readReceipt: readReceipt,
            showOpenButton: showOpenButton,
            lastActivityAt: lastActivityAt
        )
    }

    /// Vista previa, hora, no leídos y actividad para hilos CRM (Instagram/WhatsApp).
    func withCrmInboxPreview(
        _ preview: String,
        time: String,
        unread: Int?,
        lastActivityAt: Date?
    ) -> ChatThread {
        ChatThread(
            id: id,
            title: title,
            preview: preview,
            time: time,
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
            showOpenButton: showOpenButton,
            lastActivityAt: lastActivityAt
        )
    }

    /// Vista previa y hora cuando hay mensajes reales en el DM de equipo.
    func withDirectMessagePreview(_ preview: String, time: String) -> ChatThread {
        ChatThread(
            id: id,
            title: title,
            preview: preview,
            time: time,
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
            showOpenButton: showOpenButton,
            lastActivityAt: Date()
        )
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
            showOpenButton: showOpenButton,
            lastActivityAt: Date()
        )
    }

    /// Vista previa cuando hay mensajes reales en el grupo.
    func withGroupChatPreview(_ preview: String, time: String) -> ChatThread {
        ChatThread(
            id: id,
            title: title,
            preview: preview,
            time: time,
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
            showOpenButton: showOpenButton,
            lastActivityAt: Date()
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
            showOpenButton: false,
            lastActivityAt: nil
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
            showOpenButton: false,
            lastActivityAt: Date()
        )
    }

    static let samples: [ChatThread] = []
}
