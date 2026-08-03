import AVFoundation
import Photos
import SwiftUI
import PhotosUI
import Supabase
import UIKit

// MARK: - Preferencia (barra inferior alineada con el ancho del chat)

private struct ChatHorizontalPadding: Equatable {
    var leading: CGFloat
    var trailing: CGFloat
}

private struct ChatInputBarHorizontalPaddingKey: PreferenceKey {
    static var defaultValue: ChatHorizontalPadding {
        ChatHorizontalPadding(leading: 20, trailing: 20)
    }

    static func reduce(value: inout ChatHorizontalPadding, nextValue: () -> ChatHorizontalPadding) {
        value = nextValue()
    }
}

// MARK: - Modelo de mensaje

/// Marcas de envío / lectura en mensajes salientes (estilo Telegram).
private enum OutgoingReceipt: Equatable {
    case sent
    case delivered
    case read
}

private struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let text: String?
    let image: UIImage?
    /// Imagen alojada en una URL (la del cliente por WhatsApp/Instagram).
    let remoteImageURL: URL?
    /// Nota de voz remota (WhatsApp/Instagram) o archivo local mientras se envía.
    let remoteAudioURL: URL?
    /// Ruta en bucket `team_direct_voice` (prefijo en fila `body`).
    let voiceStoragePath: String?
    let isOutgoing: Bool
    let time: String
    /// Orden cronológico respecto a tareas del coordinador y otros mensajes.
    let sortKey: Date
    /// Solo salientes; `nil` en entrantes.
    let receipt: OutgoingReceipt?
    /// Remitente del mensaje (para denuncias / bloqueo).
    let senderUserId: UUID?

    init(
        id: UUID = UUID(),
        text: String,
        isOutgoing: Bool,
        time: String,
        receipt: OutgoingReceipt? = nil,
        sortKey: Date = Date(),
        voiceStoragePath: String? = nil,
        senderUserId: UUID? = nil
    ) {
        self.id = id
        self.text = text
        self.image = nil
        self.remoteImageURL = nil
        self.remoteAudioURL = nil
        self.voiceStoragePath = voiceStoragePath
        self.isOutgoing = isOutgoing
        self.time = time
        self.sortKey = sortKey
        self.receipt = isOutgoing ? (receipt ?? .read) : nil
        self.senderUserId = senderUserId
    }

    init(
        id: UUID = UUID(),
        image: UIImage,
        caption: String? = nil,
        isOutgoing: Bool,
        time: String,
        receipt: OutgoingReceipt? = nil,
        sortKey: Date = Date(),
        voiceStoragePath: String? = nil,
        senderUserId: UUID? = nil
    ) {
        self.id = id
        self.text = caption
        self.image = image
        self.remoteImageURL = nil
        self.remoteAudioURL = nil
        self.voiceStoragePath = voiceStoragePath
        self.isOutgoing = isOutgoing
        self.time = time
        self.sortKey = sortKey
        self.receipt = isOutgoing ? (receipt ?? .read) : nil
        self.senderUserId = senderUserId
    }

    /// Mensaje con imagen remota (URL) y, opcionalmente, un texto/caption debajo.
    init(
        id: UUID = UUID(),
        remoteImageURL: URL,
        caption: String? = nil,
        isOutgoing: Bool,
        time: String,
        receipt: OutgoingReceipt? = nil,
        sortKey: Date = Date(),
        senderUserId: UUID? = nil
    ) {
        self.id = id
        self.text = caption
        self.image = nil
        self.remoteImageURL = remoteImageURL
        self.remoteAudioURL = nil
        self.voiceStoragePath = nil
        self.isOutgoing = isOutgoing
        self.time = time
        self.sortKey = sortKey
        self.receipt = isOutgoing ? (receipt ?? .read) : nil
        self.senderUserId = senderUserId
    }

    init(
        id: UUID,
        voiceStoragePath: String,
        isOutgoing: Bool,
        time: String,
        receipt: OutgoingReceipt?,
        sortKey: Date,
        senderUserId: UUID? = nil
    ) {
        self.id = id
        self.text = nil
        self.image = nil
        self.remoteImageURL = nil
        self.remoteAudioURL = nil
        self.voiceStoragePath = voiceStoragePath
        self.isOutgoing = isOutgoing
        self.time = time
        self.sortKey = sortKey
        self.receipt = isOutgoing ? (receipt ?? .read) : nil
        self.senderUserId = senderUserId
    }

    init(
        id: UUID = UUID(),
        remoteAudioURL: URL,
        isOutgoing: Bool,
        time: String,
        receipt: OutgoingReceipt? = nil,
        sortKey: Date = Date(),
        senderUserId: UUID? = nil
    ) {
        self.id = id
        self.text = nil
        self.image = nil
        self.remoteImageURL = nil
        self.remoteAudioURL = remoteAudioURL
        self.voiceStoragePath = nil
        self.isOutgoing = isOutgoing
        self.time = time
        self.sortKey = sortKey
        self.receipt = isOutgoing ? (receipt ?? .read) : nil
        self.senderUserId = senderUserId
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

/// DM equipo: mensajes en orden cronológico.
private enum TeamDirectTimelineItem: Identifiable {
    case message(ChatMessage)

    var id: UUID {
        switch self {
        case .message(let m): return m.id
        }
    }

    var sortKey: Date {
        switch self {
        case .message(let m): return m.sortKey
        }
    }
}

// MARK: - Vista de conversación

struct ChatConversationView: View {
    let thread: ChatThread

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var chatInbox: ChatInboxStore
    @EnvironmentObject private var communityVM: DashboardCommunityViewModel
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var moderation: UserModerationStore
    @State private var liveMessages: [ChatMessage] = []
    @State private var draft = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var teamDirectRows: [TeamDirectMessagesService.Row] = []
    @State private var teamDirectChannel: RealtimeChannelV2?
    @State private var teamDirectLoadError: String?
    @State private var teamGroupRows: [TeamGroupMessagesService.Row] = []
    @State private var teamGroupChannel: RealtimeChannelV2?
    @State private var teamGroupLoadError: String?
    /// Mensajes reales del CRM (WhatsApp/Instagram) para hilos de «Generales».
    @State private var crmRows: [CrmChatService.Message] = []
    /// Tras el primer pintado, los siguientes scrolls al final pueden animarse.
    @State private var didInitialChatScroll = false

    /// Mismos márgenes que el scroll (sincroniza la barra inferior al salir del GeometryReader).
    @State private var inputBarHorizontalPadding = ChatHorizontalPadding(leading: 20, trailing: 20)

    @StateObject private var chatDictationTranscriber = LiveSpeechTranscriber()
    @State private var isChatDictating = false
    @State private var isRecordingTeamVoice = false
    @State private var isSendingVoiceNote = false
    @State private var isSendingCrmMessage = false
    @State private var isSendingImage = false
    @State private var teamVoiceRecorder: AVAudioRecorder?
    @State private var teamVoiceURL: URL?
    @State private var teamVoiceError: String?
    /// Gesto hold-to-record (estilo Telegram).
    @GestureState private var voiceHoldActive = false
    @GestureState private var voiceGestureRecording = false
    @GestureState private var voiceDragTranslation: CGSize = .zero
    @State private var voiceLastDragTranslation: CGSize = .zero
    @State private var voiceRecorderStartedAt: Date = .now
    @State private var voicePlayDiscardAnimation = false
    @State private var voiceDisableComposerInteraction = false
    /// Hands-free: soltó tras deslizar hacia arriba.
    @State private var isVoiceRecordingLocked = false
    @State private var voiceRecordPulse = false
    private let voiceCancelDistance: CGFloat = 64
    private let voiceLockDistance: CGFloat = 72
    private let voiceRecordingBallSize: CGFloat = 86
    @State private var showAttachPhotoPicker = false
    /// Altura medida del UITextView (crece hasta el tope; luego scroll interno).
    @State private var composerMeasuredTextHeight: CGFloat = 40
    @State private var isComposerKeyboardVisible = false
    @State private var composerFocusToken = 0
    @State private var reportTarget: ModerationTarget?
    @State private var showBlockConfirm = false
    @State private var moderationAlertMessage: String?
    @State private var showModerationAlert = false
    @State private var showObjectionableContentAlert = false
    @State private var imageLightboxItem: GrooChatImageLightboxItem?
    @State private var showPeerProfile = false
    /// Frames para el menú contextual: clase mutable (no dispara re-render al scrollear).
    @State private var messageFrameStore = ChatMessageFrameStore()
    @State private var presentedMessageMenu: PresentedMessageMenu?
    @State private var messageReactions: [UUID: String] = [:]
    @State private var replyDraftMessage: ChatMessage?
    @State private var editingMessage: ChatMessage?
    /// Texto editado localmente mientras se sincroniza con el servidor.
    @State private var messageTextOverrides: [UUID: String] = [:]
    /// Mensajes marcados como editados (etiqueta «Editado» estilo Instagram).
    @State private var editedMessageIds: Set<UUID> = []
    @State private var saveImageAlertMessage: String?

    /// Instagram: solo se puede editar texto saliente en los primeros 15 minutos.
    private static let instagramEditWindow = CrmChatService.instagramEditWindow

    private var isInstagramLeadChat: Bool {
        usesCrmServer && thread.socialSource == .instagram
    }

    private struct PresentedMessageMenu: Identifiable {
        let id: UUID
        let message: ChatMessage
        let frame: CGRect
    }

    private struct ModerationTarget: Identifiable {
        let id = UUID()
        let userId: UUID
        let userName: String
        let contentType: UserModerationService.ContentType
        let contentId: UUID?
        let contentPreview: String?
    }

    private var mockMsgs: [ChatMessage] {
        Self.mockMessages(for: thread)
    }

    private var usesTeamDirectServer: Bool {
        thread.kind == .teamDirect && thread.peerUserId != nil && auth.session != nil
    }

    private var usesTeamGroupServer: Bool {
        thread.kind == .teamGroup && auth.session != nil
    }

    /// Hilo «Generales» conectado al CRM real (WhatsApp/Instagram del concesionario).
    private var usesCrmServer: Bool {
        thread.kind == .lead
            && chatInbox.crmConversationIdByThread[thread.id] != nil
            && auth.session != nil
    }

    /// Paciente de prueba: todo local (texto, foto, audio) sin CRM ni mentor.
    private var usesPatientLocalChat: Bool {
        thread.kind == .patientLocal
    }

    private var stackedConversationMessages: [ChatMessage] {
        let base: [ChatMessage]
        if usesTeamGroupServer {
            base = teamGroupUIMessages + liveMessages
        } else if usesTeamDirectServer {
            base = teamDirectUIMessages + liveMessages
        } else if usesCrmServer {
            base = mergedCrmConversationMessages
        } else if thread.kind == .lead || usesPatientLocalChat {
            base = liveMessages
        } else {
            base = mockMsgs + liveMessages
        }
        return base
    }

    /// Mensajes CRM sin duplicar optimistas locales ni ecos repetidos del servidor.
    private var mergedCrmConversationMessages: [ChatMessage] {
        let server = deduplicatedCrmUIMessages
        let serverOutgoingTexts = Set(
            server.filter(\.isOutgoing).compactMap(\.text).map(normalizeCrmMessageText)
        )
        let pending = liveMessages.filter { msg in
            guard msg.isOutgoing else { return false }
            if let text = msg.text {
                return !serverOutgoingTexts.contains(normalizeCrmMessageText(text))
            }
            if msg.image != nil {
                let hasServerImage = server.contains { serverMsg in
                    guard serverMsg.isOutgoing else { return false }
                    guard serverMsg.image != nil || serverMsg.remoteImageURL != nil else { return false }
                    return abs(serverMsg.sortKey.timeIntervalSince(msg.sortKey)) < 240
                }
                return !hasServerImage
            }
            return false
        }
        return server + pending
    }

    private var deduplicatedCrmUIMessages: [ChatMessage] {
        Self.deduplicateAdjacentOutgoing(crmUIMessages.sorted { $0.sortKey < $1.sortKey })
    }

    private func normalizeCrmMessageText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func deduplicateAdjacentOutgoing(_ messages: [ChatMessage]) -> [ChatMessage] {
        var result: [ChatMessage] = []
        for msg in messages {
            if let last = result.last,
               last.isOutgoing == msg.isOutgoing,
               last.text == msg.text,
               abs(last.sortKey.timeIntervalSince(msg.sortKey)) < 180 {
                continue
            }
            result.append(msg)
        }
        return result
    }

    /// Mensajes reales del CRM mapeados a burbujas (cliente = entrante; IA/equipo = saliente).
    private var crmUIMessages: [ChatMessage] {
        crmRows
            .map { row -> ChatMessage in
                let incoming = CrmChatService.messageIsFromContact(row.senderType)
                let id = CrmChatService.stableUUID(for: "msg:\(row.id)")
                let time = CrmChatService.clockTime(fromISO: row.createdAt)
                let sortKey = CrmChatService.parseISO(row.createdAt) ?? Date()
                let receipt: OutgoingReceipt? = incoming ? nil : .read
                let rawText = (row.textContent ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                // 1) ¿Es AUDIO / nota de voz?
                if CrmChatService.isAudioMessage(row), let audioURL = CrmChatService.audioURL(for: row) {
                    return ChatMessage(
                        id: id,
                        remoteAudioURL: audioURL,
                        isOutgoing: !incoming,
                        time: time,
                        receipt: receipt,
                        sortKey: sortKey
                    )
                }

                // 2) ¿Es una IMAGEN? (por tipo, por extensión de la URL o por base64)
                if let imageURL = Self.crmImageURL(for: row) {
                    let caption = Self.looksLikePlaceholder(rawText) ? nil : rawText
                    return ChatMessage(
                        id: id,
                        remoteImageURL: imageURL,
                        caption: caption,
                        isOutgoing: !incoming,
                        time: time,
                        receipt: receipt,
                        sortKey: sortKey
                    )
                }

                // 3) Texto (incluye enlaces de coche, que se ven como enlace tocable).
                let text = rawText.isEmpty ? (row.mediaUrl != nil ? "📎 Archivo adjunto" : " ") : rawText
                return ChatMessage(
                    id: id,
                    text: text,
                    isOutgoing: !incoming,
                    time: time,
                    receipt: receipt,
                    sortKey: sortKey
                )
            }
            .sorted { $0.sortKey < $1.sortKey }
    }

    /// Devuelve una URL de imagen para el mensaje si es una foto (URL http o base64).
    private static func crmImageURL(for row: CrmChatService.Message) -> URL? {
        guard CrmChatService.isImageMessage(row) else { return nil }
        let type = (row.mediaType ?? row.messageType ?? "").lowercased()
        if let urlStr = row.mediaUrl, let url = URL(string: urlStr) {
            return url
        }
        if let b64 = row.mediaContent, !b64.isEmpty {
            let clean = b64.contains(",") ? String(b64.split(separator: ",").last ?? "") : b64
            let mime = type.contains("/") ? type : "image/jpeg"
            if let url = URL(string: "data:\(mime);base64,\(clean)") { return url }
        }
        return nil
    }

    private static func looksLikePlaceholder(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t == "📷 Imagen" || t == "📷 Foto" || t == "📎 Archivo adjunto" || t.count <= 1
    }

    private var teamDirectUIMessages: [ChatMessage] {
        guard let myId = auth.session?.user.id else { return [] }
        return teamDirectRows
            .filter { !moderation.isBlocked($0.senderId) }
            .map { Self.chatMessage(from: $0, myUserId: myId) }
    }

    private var teamGroupUIMessages: [ChatMessage] {
        guard let myId = auth.session?.user.id else { return [] }
        return teamGroupRows
            .filter { !moderation.isBlocked($0.senderId) }
            .map {
                Self.chatMessageGroup(from: $0, myUserId: myId, directory: communityVM.directory)
            }
    }

    /// Mensajes de texto e imágenes del DM de equipo.
    private var teamDirectTimelineItems: [TeamDirectTimelineItem] {
        guard usesTeamDirectServer else { return [] }
        let msgs = (teamDirectUIMessages + liveMessages)
        return msgs
            .sorted {
                if $0.sortKey != $1.sortKey { return $0.sortKey < $1.sortKey }
                return $0.id.uuidString < $1.id.uuidString
            }
            .map { .message($0) }
    }

    private var draftIsEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var conversationStatusLine: String {
        switch thread.kind {
        case .teamGroup:
            return "Grupo del directorio"
        case .teamDirect:
            return "Mensaje privado · equipo"
        case .lead:
            return "últ. vez recientemente"
        case .patientLocal:
            return "Chat de prueba · local"
        }
    }

    private var peerProfileSubtitle: String {
        switch thread.kind {
        case .teamGroup:
            let count = max(peerProfileMembers.count, 1)
            return count == 1 ? "1 miembro" : "\(count) miembros"
        case .teamDirect:
            return "en línea"
        case .lead:
            switch thread.socialSource {
            case .instagram: return "Instagram"
            case .whatsApp: return "WhatsApp"
            case .facebook: return "Facebook"
            case .shopify: return "Shopify"
            case .mail: return "Mail"
            case nil: return "Contacto"
            }
        case .patientLocal:
            return "Paciente · prueba local"
        }
    }

    private var peerProfileMembers: [ChatPeerMemberItem] {
        let myId = auth.session?.user.id
        switch thread.kind {
        case .teamGroup:
            return communityVM.directory
                .sorted {
                    $0.resolvedDisplayName.localizedCaseInsensitiveCompare($1.resolvedDisplayName) == .orderedAscending
                }
                .map { row in
                    ChatPeerMemberItem(
                        id: row.userId,
                        name: row.resolvedDisplayName,
                        avatarURL: row.avatarUrl.flatMap(URL.init(string:)),
                        isOwner: false,
                        isOnline: true,
                        isSelf: row.userId == myId
                    )
                }
        case .teamDirect:
            if let row = communityVM.directory.first(where: { $0.userId == thread.peerUserId }) {
                return [
                    ChatPeerMemberItem(
                        id: row.userId,
                        name: row.resolvedDisplayName,
                        avatarURL: row.avatarUrl.flatMap(URL.init(string:)),
                        isOwner: false,
                        isOnline: true,
                        isSelf: row.userId == myId
                    ),
                ]
            }
            return [
                ChatPeerMemberItem(
                    id: thread.peerUserId ?? thread.id,
                    name: thread.title,
                    avatarURL: nil,
                    isOwner: false,
                    isOnline: true,
                    isSelf: false
                ),
            ]
        case .lead, .patientLocal:
            return []
        }
    }

    private var peerSharedLibrary: ChatPeerSharedLibrary {
        var media: [ChatPeerMediaItem] = []
        var files: [ChatPeerFileItem] = []
        var voices: [ChatPeerVoiceItem] = []
        var links: [ChatPeerLinkItem] = []

        for msg in stackedConversationMessages {
            if let image = msg.image {
                media.append(
                    ChatPeerMediaItem(
                        id: msg.id,
                        remoteURL: nil,
                        localImage: image,
                        timeLabel: msg.time
                    )
                )
            } else if let url = msg.remoteImageURL {
                media.append(
                    ChatPeerMediaItem(
                        id: msg.id,
                        remoteURL: url,
                        localImage: nil,
                        timeLabel: msg.time
                    )
                )
            }

            if let audio = msg.remoteAudioURL {
                voices.append(
                    ChatPeerVoiceItem(
                        id: msg.id,
                        remoteURL: audio,
                        storagePath: msg.voiceStoragePath,
                        timeLabel: msg.time,
                        isOutgoing: msg.isOutgoing
                    )
                )
            } else if let path = msg.voiceStoragePath, !path.isEmpty {
                voices.append(
                    ChatPeerVoiceItem(
                        id: msg.id,
                        remoteURL: nil,
                        storagePath: path,
                        timeLabel: msg.time,
                        isOutgoing: msg.isOutgoing
                    )
                )
            }

            let text = (msg.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.contains("📎") || text.lowercased().contains("archivo adjunto") {
                files.append(
                    ChatPeerFileItem(
                        id: msg.id,
                        title: text.isEmpty ? "Archivo adjunto" : text,
                        timeLabel: msg.time
                    )
                )
            }

            for url in Self.extractURLs(from: text) {
                links.append(
                    ChatPeerLinkItem(
                        id: UUID(),
                        url: url,
                        title: url.host ?? url.absoluteString,
                        timeLabel: msg.time
                    )
                )
            }
        }

        return ChatPeerSharedLibrary(
            media: media.reversed(),
            files: files.reversed(),
            voices: voices.reversed(),
            links: links.reversed()
        )
    }

    private static func extractURLs(from text: String) -> [URL] {
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, options: [], range: range).compactMap(\.url)
    }

    /// Cabecera conversación estilo Telegram (blur Apple).
    private let chatToolbarNameColor = Color.black.opacity(0.9)
    private let chatToolbarStatusColor = Color.black.opacity(0.45)
    private let whatsAppFieldFill = Color.white.opacity(0.62)
    private let whatsAppSendGreen = Color(red: 0.20, green: 0.55, blue: 0.91)
    private let whatsAppComposerInset: CGFloat = 10
    /// Entrantes: blanco; texto oscuro.
    private let incomingBubbleTextColor = GrooChatTheme.incomingText
    private let incomingBubbleMetaColor = GrooChatTheme.metaText

    /// Margen desde el borde seguro hasta las burbujas (izquierda y derecha).
    private let navBarContentInset: CGFloat = 10
    /// Espacio mínimo entre burbuja y el lado opuesto dentro del ancho útil.
    private let bubbleEdgeMargin: CGFloat = 10

    private var chatBottomAnchorId: String {
        let count: Int
        if usesTeamDirectServer, thread.peerUserId != nil {
            count = teamDirectTimelineItems.count
        } else {
            count = stackedConversationMessages.count
        }
        return "chat-bottom-\(thread.id.uuidString)-\(count)"
    }

    var body: some View {
        GeometryReader { geo in
            let contentW = geo.size.width
            let leadingPad = geo.safeAreaInsets.leading + navBarContentInset
            let trailingPad = geo.safeAreaInsets.trailing + navBarContentInset
            let innerW = max(0, contentW - leadingPad - trailingPad)
            let maxBubble = max(
                120,
                min(280, innerW - bubbleEdgeMargin * 2)
            )

            ZStack(alignment: .top) {
                ConversationBackdrop()

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 3) {
                            Color.clear.frame(height: 56)

                            if usesTeamDirectServer, thread.peerUserId != nil {
                                ForEach(teamDirectTimelineItems) { item in
                                    if case .message(let msg) = item {
                                        messageBubble(msg, maxBubbleWidth: maxBubble)
                                            .frame(maxWidth: innerW)
                                            .id(msg.id)
                                            .opacity(presentedMessageMenu?.id == msg.id ? 0.01 : 1)
                                    }
                                }
                            } else {
                                ForEach(stackedConversationMessages) { msg in
                                    messageBubble(msg, maxBubbleWidth: maxBubble)
                                        .frame(maxWidth: innerW)
                                        .id(msg.id)
                                        .opacity(presentedMessageMenu?.id == msg.id ? 0.01 : 1)
                                }
                            }
                            Color.clear
                                .frame(height: 1)
                                .id(chatBottomAnchorId)
                        }
                        .frame(width: innerW, alignment: .center)
                        .padding(.leading, leadingPad)
                        .padding(.trailing, trailingPad)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    /// No cerrar el teclado al scrollear (solo al tocar el área de mensajes).
                    .scrollDismissesKeyboard(.never)
                    .scrollDisabled(presentedMessageMenu != nil)
                    .simultaneousGesture(
                        TapGesture().onEnded { _ in
                            // Solo cerrar: abrir al tocar play/scrubber abría el teclado.
                            // Para escribir se toca el composer.
                            if isComposerKeyboardVisible {
                                dismissComposerKeyboard()
                            }
                        }
                    )
                    .onChange(of: stackedConversationMessages.count) { _, _ in
                        let animate = didInitialChatScroll
                        scrollChatToBottom(proxy: proxy, animated: animate)
                        didInitialChatScroll = true
                    }
                    .onChange(of: teamDirectTimelineItems.count) { _, _ in
                        if usesTeamDirectServer {
                            let animate = didInitialChatScroll
                            scrollChatToBottom(proxy: proxy, animated: animate)
                            didInitialChatScroll = true
                        }
                    }
                    .onAppear {
                        scrollChatToBottom(proxy: proxy, animated: false)
                        didInitialChatScroll = stackedConversationMessages.count > 0
                    }
                }

                VStack(spacing: 0) {
                    whatsAppConversationHeader
                        .opacity(presentedMessageMenu == nil ? 1 : 0)
                        .allowsHitTesting(presentedMessageMenu == nil)

                    // Observación aislada: no invalida LazyVStack/mensajes al hacer play/pause.
                    if presentedMessageMenu == nil {
                        ChatVoiceMiniPlayerSlot()
                            .padding(.top, 4)
                            .padding(.bottom, 2)
                    }
                }

                if let menu = presentedMessageMenu {
                    ChatMessageActionOverlay(
                        bubbleFrame: menu.frame,
                        isOutgoing: menu.message.isOutgoing,
                        receiptCaption: messageMenuReceiptCaption(for: menu.message),
                        menuItems: messageMenuItems(for: menu.message),
                        reactions: ChatMessageReactionCatalog.default,
                        bubble: {
                            focusedMessageBubble(menu.message, maxBubbleWidth: maxBubble)
                        },
                        onReaction: { emoji in
                            messageReactions[menu.message.id] = emoji
                        },
                        onAction: { action in
                            handleMessageMenuAction(action, for: menu.message)
                        },
                        onDismiss: {
                            presentedMessageMenu = nil
                        }
                    )
                    .transition(.opacity)
                    .zIndex(50)
                }
            }
            .coordinateSpace(name: "chatConversationOverlay")
            .onPreferenceChange(ChatMessageFramePreferenceKey.self) { messageFrameStore.replaceAll($0) }
            .frame(maxWidth: contentW, maxHeight: .infinity)
            .background(alignment: .topLeading) {
                Color.clear.preference(
                    key: ChatInputBarHorizontalPaddingKey.self,
                    value: ChatHorizontalPadding(
                        leading: leadingPad,
                        trailing: trailingPad
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onPreferenceChange(ChatInputBarHorizontalPaddingKey.self) { inputBarHorizontalPadding = $0 }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if presentedMessageMenu == nil {
                inputBarChrome(
                    leadingPad: inputBarHorizontalPadding.leading,
                    trailingPad: inputBarHorizontalPadding.trailing
                )
            }
        }
        .alert("Imagen", isPresented: Binding(
            get: { saveImageAlertMessage != nil },
            set: { if !$0 { saveImageAlertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { saveImageAlertMessage = nil }
        } message: {
            Text(saveImageAlertMessage ?? "")
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .enableSwipeBackToPop()
        .onChange(of: selectedPhoto) { _, newItem in
            Task { await handleSelectedPhoto(newItem) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isComposerKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isComposerKeyboardVisible = false
        }
        .onAppear {
            if thread.kind == .lead {
                chatInbox.activeLeadThreadId = thread.id
                // Muestra al instante lo cacheado; la red refresca en segundo plano.
                if crmRows.isEmpty, let cached = chatInbox.cachedCrmMessages(for: thread.id) {
                    crmRows = cached
                }
            }
            if usesPatientLocalChat, liveMessages.isEmpty {
                seedPatientLocalWelcomeIfNeeded()
            }
            if usesTeamDirectServer, let peer = thread.peerUserId {
                chatInbox.activeTeamDirectPeerId = peer
            }
            if usesTeamGroupServer {
                chatInbox.activeTeamGroupChatOpen = true
            }
            chatInbox.markThreadAsRead(thread.id)
            if usesCrmServer {
                Task {
                    await chatInbox.markCrmThreadAsRead(
                        threadId: thread.id,
                        accessToken: auth.session?.accessToken
                    )
                }
            }
        }
        .onDisappear {
            stopChatDictationIfNeeded()
            cancelTeamVoiceNoteRecording()
            // No limpiar activeLeadThreadId: la conversación debe seguir abierta al
            // cambiar de pestaña. Se limpia solo al volver a la bandeja.
            chatInbox.activeTeamDirectPeerId = nil
            chatInbox.activeTeamGroupChatOpen = false
            Task {
                if let ch = teamDirectChannel {
                    await SupabaseClientProvider.shared.removeChannel(ch)
                    await MainActor.run { teamDirectChannel = nil }
                }
                if let ch = teamGroupChannel {
                    await SupabaseClientProvider.shared.removeChannel(ch)
                    await MainActor.run { teamGroupChannel = nil }
                }
            }
        }
        .task(id: "\(thread.id.uuidString)-\(auth.session?.user.id.uuidString ?? "none")") {
            switch thread.kind {
            case .teamGroup:
                await runTeamGroupSessionIfNeeded()
            case .teamDirect:
                await runTeamDirectSessionIfNeeded()
            case .lead:
                await runCrmSessionIfNeeded()
            case .patientLocal:
                break
            }
        }
        .alert("No se pudo enviar", isPresented: Binding(
            get: { teamVoiceError != nil },
            set: { if !$0 { teamVoiceError = nil } }
        )) {
            Button("Aceptar", role: .cancel) { teamVoiceError = nil }
        } message: {
            Text(teamVoiceError ?? "")
        }
        .sheet(item: $reportTarget) { target in
            ContentReportSheet(
                reportedUserName: target.userName,
                reportedUserId: target.userId,
                contentType: target.contentType,
                contentId: target.contentId,
                contentPreview: target.contentPreview
            )
            .environmentObject(moderation)
        }
        .fullScreenCover(item: $imageLightboxItem) { item in
            GrooChatImageLightbox(item: item)
        }
        /// Push desde la derecha (igual que abrir un chat), con swipe para volver.
        .navigationDestination(isPresented: $showPeerProfile) {
            ChatPeerProfileView(
                thread: thread,
                subtitle: peerProfileSubtitle,
                members: peerProfileMembers,
                library: peerSharedLibrary,
                accessToken: auth.session?.accessToken
            )
            .environmentObject(auth)
            .environmentObject(communityVM)
        }
        .confirmationDialog(
            "Bloquear usuario",
            isPresented: $showBlockConfirm,
            titleVisibility: .visible
        ) {
            Button("Bloquear y ocultar contenido", role: .destructive) {
                Task { await blockPrimaryTarget() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Dejarás de ver los mensajes de esta persona y se enviará un informe al equipo de GControl.")
        }
        .alert("Contenido no permitido", isPresented: $showObjectionableContentAlert) {
            Button("Entendido", role: .cancel) {}
        } message: {
            Text("Tu mensaje incluye lenguaje no permitido. Modifícalo antes de enviar.")
        }
        .alert("Moderación", isPresented: $showModerationAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(moderationAlertMessage ?? "")
        }
    }

    /// Barra inferior estilo Telegram (glass flotante).
    private func inputBarChrome(leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        VStack(spacing: 4) {
            if usesCrmServer {
                GrooCrmQuickRepliesBar(
                    contactTitle: thread.title,
                    isDisabled: isSendingCrmMessage || isSendingVoiceNote || isSendingImage
                ) { reply in
                    sendCrmQuickReply(reply)
                }
            }
            if let editing = editingMessage {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.orange)
                        .frame(width: 3, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Editando mensaje")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.orange)
                        Text(replyPreviewText(for: editing))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.black.opacity(0.55))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button {
                        cancelEditingMessage()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.4))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            } else if let reply = replyDraftMessage {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(GrooBrand.primary)
                        .frame(width: 3, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reply.isOutgoing ? "Tú" : thread.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(GrooBrand.primary)
                        Text(replyPreviewText(for: reply))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.black.opacity(0.55))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button {
                        replyDraftMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.4))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            messageInputBar
                .padding(.horizontal, 10)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background {
            GrooChatTheme.floatingBlurChromeBottom()
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Cabecera Telegram (blur Apple)

    private var whatsAppConversationHeader: some View {
        HStack(spacing: 8) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    if let unread = thread.unread, unread > 0 {
                        Text("\(min(unread, 99))")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.black.opacity(0.78)))
                    }
                }
                .foregroundStyle(Color.black.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background { GrooChatTheme.glassPillBackground() }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            Button {
                showPeerProfile = true
            } label: {
                VStack(spacing: 1) {
                    HStack(spacing: 4) {
                        Text(thread.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(chatToolbarNameColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        if thread.isVerified {
                            GrooVerifiedBadge(size: 13)
                        }
                    }
                    Text(conversationStatusLine)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(chatToolbarStatusColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background { GrooChatTheme.glassPillBackground() }
            }
            .buttonStyle(.plain)
            .layoutPriority(1)

            Spacer(minLength: 4)

            Button {
                showPeerProfile = true
            } label: {
                conversationHeaderAvatar
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            }
            .buttonStyle(.plain)

            if usesTeamDirectServer || usesTeamGroupServer {
                teamConversationActionsMenu
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background {
            GrooChatTheme.floatingBlurChrome()
                .ignoresSafeArea(edges: .top)
        }
    }

    private var teamConversationActionsMenu: some View {
        Menu {
            if let target = primaryModerationTarget {
                Button {
                    reportTarget = target
                } label: {
                    Label("Denunciar contenido", systemImage: "exclamationmark.bubble")
                }
                Button(role: .destructive) {
                    if let target = primaryModerationTarget {
                        reportTarget = target
                        showBlockConfirm = true
                    }
                } label: {
                    Label("Bloquear usuario", systemImage: "hand.raised.fill")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.75))
                .frame(width: 36, height: 36)
                .background { Circle().fill(.ultraThinMaterial).overlay(Circle().fill(Color.white.opacity(0.55))) }
        }
    }

    private var conversationHeaderAvatar: some View {
        ChatInboxListAvatarView(
            thread: thread,
            accessToken: auth.session?.accessToken,
            currentUserId: auth.session?.user.id,
            localProfileImage: auth.profileAvatarImage,
            localInitials: auth.userInitials,
            diameter: 40
        )
    }

    // MARK: - Burbujas

    /// Salientes: azul claro Telegram.
    private let outgoingBubbleGradient = LinearGradient(
        colors: [
            GrooChatTheme.outgoingBubble,
            GrooChatTheme.outgoingBubble,
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
    /// Entrantes: blanco.
    private let incomingBubbleFill = GrooChatTheme.incomingBubble
    /// Hora y checks en salientes.
    private let outgoingMetaTint = GrooChatTheme.outgoingMeta
    private let outgoingMetaTintMuted = GrooChatTheme.outgoingMeta.opacity(0.75)
    private let bubblePadH: CGFloat = 10
    private let bubblePadV: CGFloat = 7
    private let bubbleCorner: CGFloat = 16
    private let outgoingBubbleTextColor = GrooChatTheme.outgoingText

    private func messageBubble(_ msg: ChatMessage, maxBubbleWidth: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            if msg.isOutgoing {
                Spacer(minLength: bubbleEdgeMargin)
            }

            VStack(alignment: msg.isOutgoing ? .trailing : .leading, spacing: 4) {
                focusedMessageBubble(msg, maxBubbleWidth: maxBubbleWidth)
                    .chatMessageFrameTracker(id: msg.id, coordinateSpace: .named("chatConversationOverlay"))
                    .onLongPressGesture(minimumDuration: 0.32) {
                        presentMessageMenu(for: msg)
                    }

                if let reaction = messageReactions[msg.id] {
                    Text(reaction)
                        .font(.system(size: 18))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.92))
                                .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                        }
                        .offset(y: -2)
                }
            }
            .frame(maxWidth: maxBubbleWidth, alignment: msg.isOutgoing ? .trailing : .leading)

            if !msg.isOutgoing {
                Spacer(minLength: bubbleEdgeMargin)
            }
        }
        .frame(maxWidth: .infinity, alignment: msg.isOutgoing ? .trailing : .leading)
    }

    @ViewBuilder
    private func focusedMessageBubble(_ msg: ChatMessage, maxBubbleWidth: CGFloat) -> some View {
        if let voicePath = msg.voiceStoragePath {
            voiceNoteBubble(
                source: .supabase(path: voicePath),
                msg: msg,
                maxBubbleWidth: maxBubbleWidth
            )
        } else if let audioURL = msg.remoteAudioURL {
            voiceNoteBubble(
                source: .remote(url: audioURL, accessToken: usesCrmServer ? auth.session?.accessToken : nil),
                msg: msg,
                maxBubbleWidth: maxBubbleWidth
            )
        } else if let image = msg.image {
            outgoingOrIncomingImageBubble(msg, image: image, maxBubbleWidth: maxBubbleWidth)
        } else if let remote = msg.remoteImageURL {
            remoteImageBubble(url: remote, msg: msg, maxBubbleWidth: maxBubbleWidth)
        } else if let text = displayText(for: msg) {
            if msg.isOutgoing {
                outgoingTextBubble(
                    text: text,
                    time: msg.time,
                    receipt: msg.receipt ?? .sent,
                    isEdited: messageShowsEditedLabel(msg),
                    maxBubbleWidth: maxBubbleWidth
                )
            } else {
                incomingTextBubble(text: text, time: msg.time, maxBubbleWidth: maxBubbleWidth)
            }
        }
    }

    private func messageShowsEditedLabel(_ msg: ChatMessage) -> Bool {
        if editedMessageIds.contains(msg.id) { return true }
        if isInstagramLeadChat,
           let row = crmRow(for: msg.id),
           let editedAt = row.editedAt,
           !editedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
    }

    private func crmRow(for messageId: UUID) -> CrmChatService.Message? {
        crmRows.first { CrmChatService.stableUUID(for: "msg:\($0.id)") == messageId }
    }

    private func crmRowId(for messageId: UUID) -> String? {
        crmRow(for: messageId)?.id
    }

    private func presentMessageMenu(for msg: ChatMessage) {
        dismissComposerKeyboard()
        guard let frame = messageFrameStore.frame(for: msg.id), frame.width > 1, frame.height > 1 else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            presentedMessageMenu = PresentedMessageMenu(id: msg.id, message: msg, frame: frame)
        }
    }

    private func messageMenuReceiptCaption(for msg: ChatMessage) -> String? {
        guard msg.isOutgoing else { return nil }
        switch msg.receipt {
        case .read:
            return "Visto"
        case .delivered:
            return "Entregado"
        case .sent, .none:
            return "Nadie lo ha visto"
        }
    }

    private func messageIsEditable(_ msg: ChatMessage) -> Bool {
        guard msg.isOutgoing else { return false }
        guard msg.voiceStoragePath == nil, msg.remoteAudioURL == nil else { return false }
        guard msg.image == nil, msg.remoteImageURL == nil else { return false }
        let text = (messageTextOverrides[msg.id] ?? msg.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if isInstagramLeadChat {
            return CrmChatService.isWithinInstagramEditWindow(sentAt: msg.sortKey)
        }
        return true
    }

    private func messageMenuItems(for msg: ChatMessage) -> [ChatMessageMenuItem] {
        var items: [ChatMessageMenuItem] = []
        if messageIsEditable(msg) {
            items.append(ChatMessageMenuItem(title: "Editar", systemImage: "pencil", action: .edit))
        }
        if let text = (messageTextOverrides[msg.id] ?? msg.text)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            items.append(ChatMessageMenuItem(title: "Copiar", systemImage: "doc.on.doc", action: .copy))
        }
        if msg.image != nil || msg.remoteImageURL != nil {
            items.append(ChatMessageMenuItem(title: "Guardar imagen", systemImage: "square.and.arrow.down", action: .saveImage))
        }
        if let senderId = msg.senderUserId, !msg.isOutgoing, auth.session?.user.id != senderId {
            items.append(ChatMessageMenuItem(title: "Denunciar", systemImage: "exclamationmark.bubble", action: .report))
            items.append(
                ChatMessageMenuItem(title: "Bloquear", systemImage: "hand.raised.fill", action: .block, isDestructive: true)
            )
        }
        return items
    }

    private func handleMessageMenuAction(_ action: ChatMessageMenuAction, for msg: ChatMessage) {
        switch action {
        case .reply:
            editingMessage = nil
            replyDraftMessage = msg
        case .copy:
            let text = messageTextOverrides[msg.id] ?? msg.text
            if let text, !text.isEmpty {
                UIPasteboard.general.string = text
            }
        case .edit:
            beginEditingMessage(msg)
        case .saveImage:
            Task { await saveMessageImage(msg) }
        case .report:
            if let senderId = msg.senderUserId {
                reportTarget = moderationTarget(
                    userId: senderId,
                    contentType: usesTeamGroupServer ? .teamGroupMessage : .teamDirectMessage,
                    contentId: msg.id,
                    contentPreview: msg.text
                )
            }
        case .block:
            if let senderId = msg.senderUserId {
                reportTarget = moderationTarget(
                    userId: senderId,
                    contentType: usesTeamGroupServer ? .teamGroupMessage : .teamDirectMessage,
                    contentId: msg.id,
                    contentPreview: msg.text
                )
                showBlockConfirm = true
            }
        }
    }

    private func beginEditingMessage(_ msg: ChatMessage) {
        guard messageIsEditable(msg) else {
            if isInstagramLeadChat {
                teamVoiceError = "Instagram solo permite editar mensajes durante 15 minutos después de enviarlos."
            }
            return
        }
        replyDraftMessage = nil
        editingMessage = msg
        draft = messageTextOverrides[msg.id] ?? msg.text ?? ""
        composerFocusToken &+= 1
    }

    private func cancelEditingMessage() {
        editingMessage = nil
    }

    private func replyPreviewText(for msg: ChatMessage) -> String {
        if msg.voiceStoragePath != nil || msg.remoteAudioURL != nil {
            return "Nota de voz"
        }
        if msg.image != nil || msg.remoteImageURL != nil {
            return "Foto"
        }
        let text = (displayText(for: msg) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Mensaje" : text
    }

    private func displayText(for msg: ChatMessage) -> String? {
        messageTextOverrides[msg.id] ?? msg.text
    }

    private func applyEditedMessage(_ original: ChatMessage, newText: String) {
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if ContentModerationFilter.containsObjectionableContent(text) {
            showObjectionableContentAlert = true
            return
        }

        messageTextOverrides[original.id] = text
        if let idx = liveMessages.firstIndex(where: { $0.id == original.id }) {
            liveMessages[idx] = ChatMessage(
                id: original.id,
                text: text,
                isOutgoing: true,
                time: original.time,
                receipt: original.receipt,
                sortKey: original.sortKey,
                voiceStoragePath: original.voiceStoragePath,
                senderUserId: original.senderUserId
            )
        }

        draft = ""
        editingMessage = nil
        editedMessageIds.insert(original.id)

        if usesCrmServer,
           isInstagramLeadChat,
           let convId = chatInbox.crmConversationIdByThread[thread.id],
           let token = auth.session?.accessToken,
           let rowId = crmRowId(for: original.id) {
            Task {
                do {
                    try await CrmChatService.editMessage(
                        token: token,
                        conversationId: convId,
                        messageId: rowId,
                        text: text
                    )
                    await MainActor.run {
                        if let idx = crmRows.firstIndex(where: { $0.id == rowId }) {
                            let old = crmRows[idx]
                            crmRows[idx] = CrmChatService.Message(
                                id: old.id,
                                textContent: text,
                                senderType: old.senderType,
                                createdAt: old.createdAt,
                                messageType: old.messageType,
                                mediaUrl: old.mediaUrl,
                                mediaType: old.mediaType,
                                mediaContent: old.mediaContent,
                                mediaFilename: old.mediaFilename,
                                editedAt: ISO8601DateFormatter().string(from: Date())
                            )
                        }
                        messageTextOverrides[original.id] = nil
                    }
                } catch {
                    await MainActor.run {
                        teamVoiceError = "No se pudo editar el mensaje. \(error.localizedDescription)"
                    }
                }
            }
            return
        }

        if usesTeamDirectServer {
            Task {
                do {
                    let row = try await TeamDirectMessagesService.updateBody(
                        id: original.id,
                        body: text,
                        client: SupabaseClientProvider.shared
                    )
                    await MainActor.run {
                        applyTeamDirectUpdate(row)
                        editedMessageIds.insert(original.id)
                        messageTextOverrides[original.id] = nil
                    }
                } catch {
                    await MainActor.run {
                        teamVoiceError = "No se pudo guardar la edición en el servidor. Se mantiene en este dispositivo."
                    }
                }
            }
            return
        }

        if usesTeamGroupServer {
            Task {
                do {
                    let row = try await TeamGroupMessagesService.updateBody(
                        id: original.id,
                        body: text,
                        client: SupabaseClientProvider.shared
                    )
                    await MainActor.run {
                        if let i = teamGroupRows.firstIndex(where: { $0.id == row.id }) {
                            teamGroupRows[i] = row
                        }
                        editedMessageIds.insert(original.id)
                        messageTextOverrides[original.id] = nil
                    }
                } catch {
                    await MainActor.run {
                        teamVoiceError = "No se pudo guardar la edición en el servidor. Se mantiene en este dispositivo."
                    }
                }
            }
        }
        // CRM / mock: queda el override local (la API externa no edita mensajes enviados).
    }

    @MainActor
    private func saveMessageImage(_ msg: ChatMessage) async {
        let image: UIImage?
        if let local = msg.image {
            image = local
        } else if let url = msg.remoteImageURL {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                image = UIImage(data: data)
            } catch {
                saveImageAlertMessage = "No se pudo descargar la imagen."
                return
            }
        } else {
            image = nil
        }
        guard let image else {
            saveImageAlertMessage = "No hay imagen para guardar."
            return
        }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveImageAlertMessage = "Activa el acceso a Fotos para guardar la imagen."
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            saveImageAlertMessage = "Imagen guardada en Fotos."
        } catch {
            saveImageAlertMessage = "No se pudo guardar la imagen."
        }
    }

    /// Burbuja con la imagen que mandó el cliente (foto por WhatsApp/Instagram).
    @ViewBuilder
    private func remoteImageBubble(url: URL, msg: ChatMessage, maxBubbleWidth: CGFloat) -> some View {
        let side = min(maxBubbleWidth, 260)
        VStack(alignment: msg.isOutgoing ? .trailing : .leading, spacing: 4) {
            chatImageFrame(side: side) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        ZStack {
                            Color.black.opacity(0.25)
                            Image(systemName: "photo")
                                .font(.system(size: 28))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    default:
                        ZStack {
                            Color.black.opacity(0.2)
                            ProgressView().tint(.white)
                        }
                    }
                }
            } metaOverlay: {
                imageMetaOverlay(time: msg.time, receipt: msg.isOutgoing ? msg.receipt : nil)
            } onTap: {
                imageLightboxItem = .remote(url)
            }

            if let caption = msg.text, !caption.trimmingCharacters(in: .whitespaces).isEmpty,
               !Self.looksLikePlaceholder(caption) {
                if msg.isOutgoing {
                    outgoingTextBubble(text: caption, time: msg.time, receipt: msg.receipt ?? .sent, maxBubbleWidth: maxBubbleWidth)
                } else {
                    incomingTextBubble(text: caption, time: msg.time, maxBubbleWidth: maxBubbleWidth)
                }
            }
        }
    }

    @ViewBuilder
    private func chatImageFrame<Content: View, Meta: View>(
        side: CGFloat,
        @ViewBuilder content: () -> Content,
        @ViewBuilder metaOverlay: () -> Meta,
        onTap: @escaping () -> Void
    ) -> some View {
        content()
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: bubbleCorner, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                metaOverlay()
                    .padding(8)
            }
            .contentShape(RoundedRectangle(cornerRadius: bubbleCorner, style: .continuous))
            .onTapGesture(perform: onTap)
    }

    private func imageMetaOverlay(time: String, receipt: OutgoingReceipt?) -> some View {
        HStack(spacing: 3) {
            Text(time)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
            if let receipt {
                imageReceiptMarks(receipt)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background {
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.42))
        }
    }

    @ViewBuilder
    private func imageReceiptMarks(_ receipt: OutgoingReceipt) -> some View {
        switch receipt {
        case .sent:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
        case .delivered:
            HStack(spacing: -4) {
                Image(systemName: "checkmark")
                Image(systemName: "checkmark")
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white.opacity(0.92))
        case .read:
            HStack(spacing: -4) {
                Image(systemName: "checkmark")
                Image(systemName: "checkmark")
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(GrooChatTheme.readChecks)
        }
    }

    private func voiceNoteBubble(
        source: VoiceAudioSource,
        msg: ChatMessage,
        maxBubbleWidth: CGFloat
    ) -> some View {
        VoiceNoteBubbleView(
            source: source,
            messageId: msg.id.uuidString,
            speakerTitle: msg.isOutgoing ? "Tú" : thread.title,
            chatSubtitle: thread.title,
            threadId: thread.id,
            isOutgoing: msg.isOutgoing,
            time: msg.time,
            receipt: msg.receipt,
            maxBubbleWidth: maxBubbleWidth
        )
    }

    private func incomingTextBubble(text: String, time: String, maxBubbleWidth: CGFloat) -> some View {
        let displayText = ContentModerationFilter.sanitizeForDisplay(text)
        let shape = GrooMessageBubbleShape(isOutgoing: false, isLastInGroup: true)

        return Group {
            if chatTextFitsSingleLineWithMeta(text: displayText, time: time, maxBubbleWidth: maxBubbleWidth, outgoing: false, receipt: nil) {
                HStack(alignment: .bottom, spacing: 6) {
                    Text(displayText)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(incomingBubbleTextColor)
                        .lineLimit(1)
                    Text(time)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(incomingBubbleMetaColor)
                }
                .padding(.horizontal, bubblePadH)
                .padding(.vertical, bubblePadV)
                .background {
                    shape.fill(incomingBubbleFill)
                        .shadow(color: .black.opacity(0.07), radius: 3, y: 1)
                }
            } else {
                Text(displayText)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(incomingBubbleTextColor)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)
                    .padding(.trailing, 52)
                    .padding(.bottom, 2)
                    .overlay(alignment: .bottomTrailing) {
                        Text(time)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(incomingBubbleMetaColor)
                    }
                    .padding(.horizontal, bubblePadH)
                    .padding(.vertical, bubblePadV)
                    .background {
                        shape.fill(incomingBubbleFill)
                            .shadow(color: .black.opacity(0.07), radius: 3, y: 1)
                    }
            }
        }
        .frame(maxWidth: maxBubbleWidth, alignment: .leading)
    }

    private func incomingTextMultiline(text: String, time: String, contentCap: CGFloat, shape: RoundedRectangle) -> some View {
        // Legacy helper kept for call sites that still pass RoundedRectangle; unused by Telegram layout.
        Text(text)
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(incomingBubbleTextColor)
            .padding(.horizontal, bubblePadH)
            .padding(.vertical, bubblePadV)
            .background { shape.fill(incomingBubbleFill) }
            .frame(maxWidth: contentCap, alignment: .leading)
            .accessibilityHidden(true)
            .hidden()
    }

    private func outgoingTextBubble(
        text: String,
        time: String,
        receipt: OutgoingReceipt,
        isEdited: Bool = false,
        maxBubbleWidth: CGFloat
    ) -> some View {
        let shape = GrooMessageBubbleShape(isOutgoing: true, isLastInGroup: true)

        return Group {
            if chatTextFitsSingleLineWithMeta(
                text: text,
                time: time,
                maxBubbleWidth: maxBubbleWidth,
                outgoing: true,
                receipt: receipt,
                isEdited: isEdited
            ) {
                HStack(alignment: .bottom, spacing: 6) {
                    Text(text)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(outgoingBubbleTextColor)
                        .lineLimit(1)
                    outgoingMetaRow(time: time, receipt: receipt, isEdited: isEdited)
                }
                .padding(.horizontal, bubblePadH)
                .padding(.vertical, bubblePadV)
                .background {
                    shape.fill(GrooChatTheme.outgoingBubble)
                        .shadow(color: .black.opacity(0.07), radius: 3, y: 1)
                }
            } else {
                Text(text)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(outgoingBubbleTextColor)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)
                    .padding(.trailing, isEdited ? 88 : 72)
                    .padding(.bottom, 2)
                    .overlay(alignment: .bottomTrailing) {
                        outgoingMetaRow(time: time, receipt: receipt, isEdited: isEdited)
                    }
                    .padding(.horizontal, bubblePadH)
                    .padding(.vertical, bubblePadV)
                    .background {
                        shape.fill(GrooChatTheme.outgoingBubble)
                            .shadow(color: .black.opacity(0.07), radius: 3, y: 1)
                    }
            }
        }
        .frame(maxWidth: maxBubbleWidth, alignment: .trailing)
    }

    /// Evita una sola línea kilométrica: si no cabe texto+hora(+checks) en el ancho de burbuja, forzamos el layout multilínea.
    private func chatTextFitsSingleLineWithMeta(
        text: String,
        time: String,
        maxBubbleWidth: CGFloat,
        outgoing: Bool,
        receipt: OutgoingReceipt?,
        isEdited: Bool = false
    ) -> Bool {
        guard !text.contains(where: \.isNewline) else { return false }
        let inner = maxBubbleWidth - 2 * bubblePadH
        let bodyFont = UIFont.systemFont(ofSize: 16, weight: .regular)
        let metaFont = UIFont.systemFont(ofSize: 11, weight: .medium)
        let textW = (text as NSString).size(withAttributes: [.font: bodyFont]).width
        let timeW = (time as NSString).size(withAttributes: [.font: metaFont]).width
        let editedW: CGFloat = isEdited
            ? ("Editado " as NSString).size(withAttributes: [.font: metaFont]).width
            : 0
        if outgoing, let receipt {
            let checkW: CGFloat = receipt == .sent ? 13 : 17
            let row = textW + 6 + editedW + timeW + 4 + checkW
            return row <= inner
        }
        let row = textW + 6 + timeW
        return row <= inner
    }

    private func outgoingTextMultiline(text: String, time: String, receipt: OutgoingReceipt, contentCap: CGFloat, shape: RoundedRectangle) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(outgoingBubbleTextColor)
            .padding(.horizontal, bubblePadH)
            .padding(.vertical, bubblePadV)
            .background { shape.fill(GrooChatTheme.outgoingBubble) }
            .frame(maxWidth: contentCap, alignment: .trailing)
            .accessibilityHidden(true)
            .hidden()
    }

    private func outgoingMetaRow(time: String, receipt: OutgoingReceipt, isEdited: Bool = false) -> some View {
        HStack(spacing: 3) {
            if isEdited {
                Text("Editado")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(outgoingMetaTint.opacity(0.85))
            }
            Text(time)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(outgoingMetaTint)
            outgoingReceiptMarks(receipt)
        }
    }

    @ViewBuilder
    private func outgoingReceiptMarks(_ receipt: OutgoingReceipt) -> some View {
        switch receipt {
        case .sent:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(outgoingMetaTint)
        case .delivered:
            outgoingDoubleCheckmarks(foreground: outgoingMetaTintMuted)
        case .read:
            outgoingDoubleCheckmarks(foreground: GrooChatTheme.readChecks)
        }
    }

    private func outgoingDoubleCheckmarks(foreground: Color) -> some View {
        HStack(spacing: -4) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(foreground)
    }

    @ViewBuilder
    private func outgoingOrIncomingImageBubble(_ msg: ChatMessage, image: UIImage, maxBubbleWidth: CGFloat) -> some View {
        let side = min(maxBubbleWidth, 260)
        VStack(alignment: msg.isOutgoing ? .trailing : .leading, spacing: 4) {
            chatImageFrame(side: side, content: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }, metaOverlay: {
                imageMetaOverlay(time: msg.time, receipt: msg.isOutgoing ? msg.receipt : nil)
            }, onTap: {
                imageLightboxItem = .local(image)
            })

            if let caption = msg.text, !caption.trimmingCharacters(in: .whitespaces).isEmpty {
                if msg.isOutgoing {
                    outgoingTextBubble(text: caption, time: msg.time, receipt: msg.receipt ?? .sent, maxBubbleWidth: maxBubbleWidth)
                } else {
                    incomingTextBubble(text: caption, time: msg.time, maxBubbleWidth: maxBubbleWidth)
                }
            }
        }
    }

    // MARK: - Barra de entrada (estilo Telegram glass)

    /// Mismo diámetro que clip / mic / enviar → barra vacía igual de flaca.
    private let composerChromeHeight: CGFloat = 40
    private let composerFontSize: CGFloat = 16
    private let composerFieldPaddingV: CGFloat = 0
    private let composerFieldPaddingH: CGFloat = 12
    private let composerEmojiSide: CGFloat = 22
    private let composerEmojiTrailing: CGFloat = 8
    /// ~6–7 líneas; después el texto hace scroll dentro del contenedor.
    private let composerTextScrollMaxHeight: CGFloat = 148

    private var composerIsMultiline: Bool {
        draft.contains(where: \.isNewline) || draft.count > 32
    }

    private var composerShowsSingleLineChrome: Bool {
        draftIsEmpty || !composerIsMultiline
    }

    /// Alto del campo de texto: crece con el contenido y se topea para scroll.
    private var composerClampedTextHeight: CGFloat {
        if composerShowsSingleLineChrome { return composerChromeHeight }
        let h = max(composerChromeHeight, composerMeasuredTextHeight)
        return min(h, composerTextScrollMaxHeight)
    }

    private var composerFieldOuterHeight: CGFloat {
        if composerShowsSingleLineChrome { return composerChromeHeight }
        return composerClampedTextHeight + 8 // padding vertical multilínea
    }

    private var supportsHoldToRecordVoice: Bool {
        usesTeamDirectServer || usesCrmServer || usesPatientLocalChat
    }

    private var isVoiceGestureActive: Bool {
        voiceGestureRecording || isRecordingTeamVoice || isVoiceRecordingLocked
    }

    /// Solo el botón se mueve; la barra del timer se queda fija.
    private var voiceBallOffset: CGSize {
        guard isVoiceGestureActive, !isVoiceRecordingLocked else { return .zero }
        let x = min(0, max(voiceDragTranslation.width, -180))
        let y = min(0, max(voiceDragTranslation.height, -140))
        return CGSize(width: x, height: y)
    }

    private var voiceCancelProgress: CGFloat {
        min(1, max(0, -voiceDragTranslation.width / voiceCancelDistance))
    }

    private var voiceLockProgress: CGFloat {
        min(1, max(0, -voiceDragTranslation.height / voiceLockDistance))
    }

    private var isNearVoiceCancel: Bool {
        voiceCancelProgress >= 0.85 && voiceCancelProgress >= voiceLockProgress
    }

    private var isNearVoiceLock: Bool {
        voiceLockProgress >= 0.85 && voiceLockProgress > voiceCancelProgress
    }

    private var messageInputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ChatComposerAttachControl(
                isRecording: isVoiceGestureActive,
                isLockedRecording: isVoiceRecordingLocked,
                playDiscardAnimation: $voicePlayDiscardAnimation,
                action: {
                    if isVoiceRecordingLocked {
                        discardLockedVoiceRecording()
                        return
                    }
                    guard !isVoiceGestureActive, !isSendingVoiceNote, !isSendingImage else { return }
                    showAttachPhotoPicker = true
                }
            )
            .photosPicker(isPresented: $showAttachPhotoPicker, selection: $selectedPhoto, matching: .images)
            .disabled(isChatDictating || isSendingVoiceNote || isSendingImage || (isVoiceGestureActive && !isVoiceRecordingLocked))

            composerTextField
                .animation(.interpolatingSpring(duration: 0.3), value: isVoiceGestureActive)

            composerMicOrSendButton
        }
        .padding(.top, isVoiceGestureActive ? (isVoiceRecordingLocked ? 28 : 64) : 0)
        .overlay(alignment: .bottomTrailing) {
            if isVoiceGestureActive && !isVoiceRecordingLocked {
                ChatVoiceLockHint(
                    progress: voiceLockProgress,
                    isArmed: isNearVoiceLock
                )
                .padding(.trailing, max(0, (voiceRecordingBallSize - composerChromeHeight) / 2))
                .offset(y: -voiceRecordingBallSize / 2 - 18)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(.interpolatingSpring(duration: 0.4), value: voiceHoldActive)
        .animation(.interactiveSpring(duration: 0.22), value: voiceBallOffset.width)
        .animation(.interactiveSpring(duration: 0.22), value: voiceBallOffset.height)
        .animation(.easeInOut(duration: 0.14), value: composerIsMultiline)
        .animation(.easeInOut(duration: 0.14), value: draftIsEmpty)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isVoiceRecordingLocked)
        .onChange(of: voiceGestureRecording) { _, recording in
            handleVoiceGestureRecordingChange(recording)
        }
        .onChange(of: voiceDragTranslation) { _, translation in
            // GestureState vuelve a .zero al soltar; no pisar el último arrastre útil.
            if voiceGestureRecording, translation != .zero {
                voiceLastDragTranslation = translation
            }
        }
        .onChange(of: isVoiceGestureActive) { _, active in
            if active {
                voiceRecordPulse = false
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                    voiceRecordPulse = true
                }
            } else {
                voiceRecordPulse = false
            }
        }
        .overlay {
            if voiceDisableComposerInteraction {
                Rectangle()
                    .foregroundStyle(.clear)
                    .contentShape(Rectangle())
                    .transition(.identity)
            }
        }
    }

    private var composerTextField: some View {
        ZStack(alignment: composerShowsSingleLineChrome ? .trailing : .bottomTrailing) {
            ZStack(alignment: composerShowsSingleLineChrome ? .leading : .topLeading) {
                ComposerTextView(
                    text: $draft,
                    measuredHeight: $composerMeasuredTextHeight,
                    focusToken: composerFocusToken,
                    maxHeight: composerTextScrollMaxHeight,
                    fontSize: composerFontSize,
                    centerVerticallyWhenSingleLine: true
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: composerClampedTextHeight, alignment: .topLeading)
                .padding(.trailing, composerEmojiSide + 6)
                .opacity((isChatDictating || isVoiceGestureActive || isSendingVoiceNote) ? 0 : 1)
                .allowsHitTesting(!isVoiceGestureActive)

                if isVoiceGestureActive {
                    HStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .opacity(voiceRecordPulse ? 1 : 0.35)
                                .animation(
                                    .easeInOut(duration: 0.85).repeatForever(autoreverses: true),
                                    value: voiceRecordPulse
                                )

                            Text(voiceRecorderStartedAt, style: .timer)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.72))
                                .monospacedDigit()
                        }

                        Spacer(minLength: 4)

                        if isVoiceRecordingLocked {
                            Button {
                                discardLockedVoiceRecording()
                            } label: {
                                Text("Cancelar")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(GrooChatTheme.telegramBlue)
                            }
                            .buttonStyle(.plain)
                        } else {
                            ChatSlideToCancelText(text: isNearVoiceCancel ? "Cancelar" : "Desliza para cancelar")
                                .opacity(isNearVoiceLock ? 0.25 : (0.55 + 0.45 * Double(voiceCancelProgress)))
                                .offset(x: -10 * voiceCancelProgress)
                        }
                    }
                    .padding(.trailing, isVoiceRecordingLocked ? 6 : 18)
                    .transition(.opacity)
                } else if isSendingVoiceNote {
                    Text("Enviando audio…")
                        .font(.system(size: composerFontSize))
                        .foregroundStyle(Color.black.opacity(0.4))
                        .allowsHitTesting(false)
                } else if isSendingImage {
                    Text("Enviando imagen…")
                        .font(.system(size: composerFontSize))
                        .foregroundStyle(Color.black.opacity(0.4))
                        .allowsHitTesting(false)
                } else if isChatDictating {
                    Group {
                        if chatDictationTranscriber.partialText.isEmpty {
                            Text("Escuchando…")
                                .font(.system(size: composerFontSize))
                                .foregroundStyle(Color.black.opacity(0.35))
                        } else {
                            Text(chatDictationTranscriber.partialText)
                                .font(.system(size: composerFontSize))
                                .foregroundStyle(Color.black.opacity(0.85))
                        }
                    }
                    .allowsHitTesting(false)
                } else if draftIsEmpty {
                    Text("Mensaje")
                        .font(.system(size: composerFontSize))
                        .foregroundStyle(Color.black.opacity(0.35))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .allowsHitTesting(false)
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: composerChromeHeight,
                maxHeight: composerClampedTextHeight,
                alignment: composerShowsSingleLineChrome ? .center : .topLeading
            )

            /// Siempre a la derecha (centrado en 1 línea; abajo si crece).
            if !isVoiceGestureActive {
                Image(systemName: "face.smiling")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.35))
                    .frame(width: composerEmojiSide, height: composerEmojiSide)
                    .padding(.trailing, composerEmojiTrailing)
                    .padding(.bottom, composerShowsSingleLineChrome ? 0 : composerEmojiBottomInset)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, composerFieldPaddingH)
        .padding(.trailing, 4)
        .padding(.vertical, composerShowsSingleLineChrome ? 0 : 4)
        .frame(height: composerFieldOuterHeight, alignment: .bottom)
        .background { composerFieldBackground }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.easeInOut(duration: 0.12), value: composerClampedTextHeight)
    }

    private var composerMicOrSendButton: some View {
        /// Círculo grande sólido al grabar / anclado (sin halo ni glow).
        let recordingBall = isVoiceGestureActive
        let ballScale = recordingBall
            ? voiceRecordingBallSize / composerChromeHeight
            : (voiceHoldActive ? 1.1 : 1)
        let iconSize: CGFloat = recordingBall ? 15 : 18

        return Image(systemName: composerActionSymbol)
            .font(.system(size: iconSize, weight: recordingBall ? .bold : .semibold))
            .foregroundStyle(composerActionUsesFilledCircle ? Color.white : Color.black.opacity(0.65))
            .contentTransition(.symbolEffect(.replace, options: .default.speed(1.2)))
            .frame(width: composerChromeHeight, height: composerChromeHeight)
            .background {
                if composerActionUsesFilledCircle {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.34, green: 0.64, blue: 0.99),
                                    GrooChatTheme.telegramBlue,
                                    Color(red: 0.18, green: 0.46, blue: 0.90),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(
                            color: recordingBall ? .clear : GrooChatTheme.telegramBlue.opacity(0.28),
                            radius: recordingBall ? 0 : 6,
                            y: recordingBall ? 0 : 2
                        )
                } else {
                    GrooChatTheme.glassCircleBackground()
                }
            }
            .scaleEffect(ballScale)
            .offset(isVoiceRecordingLocked ? .zero : voiceBallOffset)
            .opacity(isSendingVoiceNote ? 0.65 : (isNearVoiceCancel ? 0.55 : 1))
            .overlay {
                if isSendingVoiceNote {
                    ProgressView().tint(.white).scaleEffect(0.7)
                }
            }
            .contentShape(Circle())
            .gesture(composerSendTapGesture, isEnabled: (!draftIsEmpty || isVoiceRecordingLocked) && !isSendingVoiceNote)
            .gesture(
                composerHoldToRecordGesture,
                isEnabled: draftIsEmpty && supportsHoldToRecordVoice && !isSendingVoiceNote && !isVoiceRecordingLocked
            )
            .onTapGesture {
                guard draftIsEmpty, !supportsHoldToRecordVoice, !isSendingVoiceNote, !isVoiceRecordingLocked else { return }
                toggleChatDictation()
            }
            .accessibilityLabel(composerActionAccessibilityLabel)
            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: recordingBall)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isVoiceRecordingLocked)
            .animation(.interactiveSpring(duration: 0.2), value: isNearVoiceLock)
            .animation(.interactiveSpring(duration: 0.2), value: isNearVoiceCancel)
    }

    private var composerActionSymbol: String {
        if !draftIsEmpty, !isVoiceGestureActive { return "paperplane.fill" }
        if isChatDictating { return "stop.fill" }
        // Anclado o deslizando arriba: flecha (ref. Telegram), círculo grande.
        if isVoiceRecordingLocked || isNearVoiceLock { return "arrow.up" }
        if isVoiceGestureActive { return "mic.fill" }
        return "mic.fill"
    }

    private var composerActionUsesFilledCircle: Bool {
        !draftIsEmpty || isVoiceGestureActive
    }

    private var composerActionAccessibilityLabel: String {
        if isSendingVoiceNote { return "Enviando audio" }
        if isVoiceRecordingLocked { return "Grabación bloqueada. Toca para enviar" }
        if !draftIsEmpty { return "Enviar mensaje" }
        if isVoiceGestureActive { return "Grabando audio. Desliza arriba para bloquear o a la izquierda para cancelar" }
        if isChatDictating { return "Detener dictado" }
        return supportsHoldToRecordVoice ? "Mantén pulsado para grabar audio" : "Dictar mensaje"
    }

    private var composerSendTapGesture: some Gesture {
        TapGesture(count: 1).onEnded { _ in
            if isVoiceRecordingLocked {
                sendLockedVoiceRecording()
            } else {
                sendMessage()
            }
        }
    }

    private var composerHoldToRecordGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.22)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .updating($voiceHoldActive) { _, state, _ in
                state = true
            }
            .updating($voiceGestureRecording) { value, state, _ in
                if case .second(_, _) = value {
                    state = true
                }
            }
            .updating($voiceDragTranslation) { value, state, _ in
                if case let .second(_, drag) = value, let drag {
                    state = drag.translation
                }
            }
    }

    private func handleVoiceGestureRecordingChange(_ recording: Bool) {
        if recording {
            isVoiceRecordingLocked = false
            voiceRecorderStartedAt = .now
            voiceLastDragTranslation = .zero
            dismissComposerKeyboard()
            if isChatDictating { stopChatDictationIfNeeded() }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task { @MainActor in
                await startTeamVoiceNoteRecording()
            }
            return
        }

        // Soltó el dedo: lock / cancel / enviar.
        let drag = voiceLastDragTranslation
        voiceLastDragTranslation = .zero

        if isVoiceRecordingLocked {
            return
        }

        let cancelScore = -drag.width
        let lockScore = -drag.height

        if lockScore >= voiceLockDistance, lockScore >= cancelScore {
            isVoiceRecordingLocked = true
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            return
        }

        if cancelScore >= voiceCancelDistance {
            voiceDisableComposerInteraction = true
            voicePlayDiscardAnimation = true
            cancelTeamVoiceNoteRecording()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.7))
                voiceDisableComposerInteraction = false
            }
            return
        }

        if isRecordingTeamVoice {
            Task { @MainActor in
                await finishTeamVoiceNoteRecordingAndSend()
            }
        }
    }

    private func discardLockedVoiceRecording() {
        guard isVoiceRecordingLocked || isRecordingTeamVoice else { return }
        isVoiceRecordingLocked = false
        voiceDisableComposerInteraction = true
        voicePlayDiscardAnimation = true
        cancelTeamVoiceNoteRecording()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.7))
            voiceDisableComposerInteraction = false
        }
    }

    private func sendLockedVoiceRecording() {
        guard isVoiceRecordingLocked else { return }
        isVoiceRecordingLocked = false
        Task { @MainActor in
            await finishTeamVoiceNoteRecordingAndSend()
        }
    }

    /// Centra la carita en la franja inferior cuando hay varias líneas.
    private var composerEmojiBottomInset: CGFloat {
        max(0, (composerChromeHeight - composerEmojiSide) / 2 - 4)
    }

    private var composerFieldBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.88))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.98), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }

    private func voiceNoteFileByteCount(at url: URL) -> UInt64? {
        guard FileManager.default.fileExists(atPath: url.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64 else { return nil }
        return size
    }

    @MainActor
    private func awaitVoiceNoteFileReady(at url: URL, minimumBytes: UInt64 = 400) async -> UInt64? {
        for _ in 0 ..< 12 {
            if let size = voiceNoteFileByteCount(at: url), size >= minimumBytes {
                return size
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return voiceNoteFileByteCount(at: url)
    }

    @MainActor
    private func cleanupVoiceNoteFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        if !ChatVoicePlaybackCoordinator.shared.isActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func requestMicPermissionForChat() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { ok in
                cont.resume(returning: ok)
            }
        }
    }

    private func mergeDictationIntoDraft(_ captured: String) {
        let t = captured.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if draft.isEmpty {
            draft = t
        } else if draft.hasSuffix(" ") {
            draft += t
        } else {
            draft += " " + t
        }
    }

    private func stopChatDictationIfNeeded() {
        guard isChatDictating else { return }
        let captured = chatDictationTranscriber.partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        chatDictationTranscriber.stopLiveTranscription()
        isChatDictating = false
        mergeDictationIntoDraft(captured)
    }

    private func toggleChatDictation() {
        if isChatDictating {
            stopChatDictationIfNeeded()
            dismissComposerKeyboard()
            return
        }
        cancelTeamVoiceNoteRecording()
        dismissComposerKeyboard()
        Task {
            let mic = await requestMicPermissionForChat()
            guard mic else { return }
            let speech = await chatDictationTranscriber.requestSpeechAuthorization()
            guard speech else { return }
            await MainActor.run {
                do {
                    try chatDictationTranscriber.startLiveTranscription()
                    isChatDictating = true
                } catch {
                    teamVoiceError = error.localizedDescription
                }
            }
        }
    }

    private func cancelTeamVoiceNoteRecording() {
        let hadRecorder = teamVoiceRecorder != nil || isRecordingTeamVoice
        teamVoiceRecorder?.stop()
        teamVoiceRecorder = nil
        if let url = teamVoiceURL {
            try? FileManager.default.removeItem(at: url)
        }
        teamVoiceURL = nil
        isRecordingTeamVoice = false
        isVoiceRecordingLocked = false
        // No apagar la sesión si hay una nota de voz sonando (sigue al salir del chat).
        if hadRecorder, !ChatVoicePlaybackCoordinator.shared.isActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func toggleVoiceNoteRecording() {
        guard !isSendingVoiceNote else { return }
        if isRecordingTeamVoice {
            Task { @MainActor in
                await finishTeamVoiceNoteRecordingAndSend()
            }
        } else {
            dismissComposerKeyboard()
            if isChatDictating { stopChatDictationIfNeeded() }
            Task { @MainActor in
                await startTeamVoiceNoteRecording()
            }
        }
    }

    @MainActor
    private func startTeamVoiceNoteRecording() async {
        guard usesTeamDirectServer || usesCrmServer || usesPatientLocalChat else { return }
        if !usesPatientLocalChat {
            guard auth.session != nil else { return }
            if usesTeamDirectServer, thread.peerUserId == nil { return }
            if usesCrmServer, chatInbox.crmConversationIdByThread[thread.id] == nil { return }
        }
        guard !isRecordingTeamVoice else { return }
        if isChatDictating { stopChatDictationIfNeeded() }
        let mic = await requestMicPermissionForChat()
        guard mic else {
            teamVoiceError = "Activa el micrófono en Ajustes para enviar notas de voz."
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dm-voice-\(UUID().uuidString).m4a")
        teamVoiceURL = url
        do {
            let av = AVAudioSession.sharedInstance()
            try av.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP]
            )
            try av.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.prepareToRecord()
            guard rec.record() else {
                throw NSError(domain: "Drflow", code: 2, userInfo: [NSLocalizedDescriptionKey: "No se pudo grabar audio."])
            }
            teamVoiceRecorder = rec
            isRecordingTeamVoice = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } catch {
            teamVoiceURL = nil
            teamVoiceRecorder = nil
            teamVoiceError = error.localizedDescription
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    @MainActor
    private func finishTeamVoiceNoteRecordingAndSend() async {
        guard isRecordingTeamVoice, !isSendingVoiceNote else { return }

        let recorder = teamVoiceRecorder
        let recordedSeconds = recorder?.currentTime ?? 0
        recorder?.stop()
        teamVoiceRecorder = nil
        isRecordingTeamVoice = false
        isVoiceRecordingLocked = false

        guard let url = teamVoiceURL else {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        teamVoiceURL = nil

        let nbytes = await awaitVoiceNoteFileReady(at: url) ?? 0
        guard recordedSeconds >= 0.35, nbytes > 400 else {
            // Toque corto / sin audio: descartar en silencio (sin alert).
            cleanupVoiceNoteFile(at: url)
            return
        }

        isSendingVoiceNote = true
        defer {
            isSendingVoiceNote = false
            if !usesPatientLocalChat {
                cleanupVoiceNoteFile(at: url)
            }
        }

        if usesPatientLocalChat {
            let now = Self.currentTimeString()
            let persisted = Self.persistLocalVoiceNote(from: url) ?? url
            liveMessages.append(
                ChatMessage(remoteAudioURL: persisted, isOutgoing: true, time: now, receipt: .sent)
            )
            chatInbox.applyPatientLocalPreview(threadId: thread.id, preview: "🎤 Audio", date: Date())
            cleanupVoiceNoteFile(at: url)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }

        if usesCrmServer,
           let convId = chatInbox.crmConversationIdByThread[thread.id],
           let token = auth.session?.accessToken {
            let now = Self.currentTimeString()
            liveMessages.append(
                ChatMessage(remoteAudioURL: url, isOutgoing: true, time: now, receipt: .sent)
            )
            do {
                try await CrmChatService.sendAudio(token: token, conversationId: convId, fileURL: url)
                await refreshCrmMessages(clearLocal: true)
                NotificationCenter.default.post(name: .messageDidRespond, object: nil)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch {
                liveMessages.removeAll { $0.remoteAudioURL == url && $0.isOutgoing }
                teamVoiceError = "No se pudo enviar la nota de voz. \(error.localizedDescription)"
            }
            return
        }

        if usesTeamDirectServer,
           let peer = thread.peerUserId,
           let myId = auth.session?.user.id {
            let path = TeamDirectVoiceStorage.makeObjectPath(senderId: myId, recipientId: peer)
            do {
                try await TeamDirectVoiceStorage.upload(fileURL: url, path: path, client: SupabaseClientProvider.shared)
                let body = TeamDirectVoiceStorage.messageBody(forStoragePath: path)
                let row = try await TeamDirectMessagesService.send(
                    recipientId: peer,
                    body: body,
                    client: SupabaseClientProvider.shared
                )
                let date = TeamDirectMessagesService.parseCreatedAt(row.createdAt) ?? Date()
                mergeTeamDirectInsert(row)
                chatInbox.applyTeamDirectOutgoing(toPeer: peer, body: row.body, date: date)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch {
                teamVoiceError = error.localizedDescription
            }
            return
        }

        teamVoiceError = "No se pudo enviar el audio en este chat."
    }

    // MARK: - Envío texto

    @MainActor
    private func handleSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        defer { selectedPhoto = nil }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }

        let caption = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !caption.isEmpty, ContentModerationFilter.containsObjectionableContent(caption) {
            showObjectionableContentAlert = true
            return
        }
        draft = ""

        if usesCrmServer,
           let convId = chatInbox.crmConversationIdByThread[thread.id],
           let token = auth.session?.accessToken {
            await sendCrmImage(image, caption: caption, conversationId: convId, token: token)
            return
        }

        let now = Self.currentTimeString()
        liveMessages.append(
            ChatMessage(
                image: image,
                caption: caption.isEmpty ? nil : caption,
                isOutgoing: true,
                time: now,
                receipt: .sent
            )
        )
        if usesPatientLocalChat {
            chatInbox.applyPatientLocalPreview(
                threadId: thread.id,
                preview: caption.isEmpty ? "📷 Foto" : caption,
                date: Date()
            )
        }
    }

    @MainActor
    private func sendCrmImage(
        _ image: UIImage,
        caption: String,
        conversationId convId: String,
        token: String
    ) async {
        guard !isSendingImage else { return }
        isSendingImage = true
        let now = Self.currentTimeString()
        let sortKey = Date()
        let optimistic = ChatMessage(
            image: image,
            caption: caption.isEmpty ? nil : caption,
            isOutgoing: true,
            time: now,
            receipt: .sent,
            sortKey: sortKey
        )
        liveMessages.append(optimistic)
        chatInbox.applyCrmLeadPreview(
            threadId: thread.id,
            preview: caption.isEmpty ? "📷 Foto" : caption,
            date: sortKey
        )

        do {
            try await CrmChatService.sendImage(
                token: token,
                conversationId: convId,
                image: image,
                caption: caption
            )
            await refreshCrmMessages(clearLocal: true)
            NotificationCenter.default.post(name: .messageDidRespond, object: nil)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            liveMessages.removeAll { $0.id == optimistic.id }
            teamVoiceError = "No se pudo enviar la imagen. \(error.localizedDescription)"
        }
        isSendingImage = false
    }

    private func sendCrmQuickReply(_ reply: GrooCrmQuickReply) {
        let text = reply.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let convId = chatInbox.crmConversationIdByThread[thread.id],
              let token = auth.session?.accessToken
        else { return }
        if ContentModerationFilter.containsObjectionableContent(text) {
            showObjectionableContentAlert = true
            return
        }
        sendCrmText(text, conversationId: convId, token: token)
    }

    private func sendCrmText(_ text: String, conversationId convId: String, token: String) {
        guard !isSendingCrmMessage else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSendingCrmMessage = true
        let now = Self.currentTimeString()
            liveMessages.append(ChatMessage(text: trimmed, isOutgoing: true, time: now, receipt: .sent))
            chatInbox.applyCrmLeadPreview(threadId: thread.id, preview: trimmed, date: Date())

        Task {
            do {
                try await CrmChatService.send(token: token, conversationId: convId, text: trimmed)
                await refreshCrmMessages(clearLocal: true)
                await MainActor.run {
                    isSendingCrmMessage = false
                    NotificationCenter.default.post(name: .messageDidRespond, object: nil)
                }
            } catch {
                await MainActor.run {
                    isSendingCrmMessage = false
                    liveMessages.removeAll { $0.text == trimmed && $0.isOutgoing }
                    if draft.isEmpty { draft = trimmed }
                    teamVoiceError = "No se pudo enviar el mensaje. \(error.localizedDescription)"
                }
            }
        }
    }

    private func sendMessage() {
        var text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let editing = editingMessage {
            applyEditedMessage(editing, newText: text)
            return
        }
        if let reply = replyDraftMessage {
            let quote = replyPreviewText(for: reply)
            text = "↩ \(quote)\n\(text)"
        }
        if ContentModerationFilter.containsObjectionableContent(text) {
            showObjectionableContentAlert = true
            return
        }
        replyDraftMessage = nil
        if usesTeamGroupServer {
            draft = ""
            Task {
                do {
                    let row = try await TeamGroupMessagesService.send(
                        body: text,
                        client: SupabaseClientProvider.shared
                    )
                    let d = TeamGroupMessagesService.parseCreatedAt(row.createdAt) ?? Date()
                    await MainActor.run {
                        mergeTeamGroupInsert(row)
                        chatInbox.applyTeamGroupOutgoing(body: row.body, date: d)
                        NotificationCenter.default.post(name: .messageDidRespond, object: nil)
                    }
                } catch {
                    await MainActor.run { draft = text }
                }
            }
            return
        }
        if usesCrmServer,
           let convId = chatInbox.crmConversationIdByThread[thread.id],
           let token = auth.session?.accessToken {
            draft = ""
            sendCrmText(text, conversationId: convId, token: token)
            return
        }
        if usesTeamDirectServer, let peer = thread.peerUserId {
            draft = ""
            Task {
                do {
                    let row = try await TeamDirectMessagesService.send(
                        recipientId: peer,
                        body: text,
                        client: SupabaseClientProvider.shared
                    )
                    await MainActor.run {
                        mergeTeamDirectInsert(row)
                        chatInbox.applyTeamDirectOutgoing(
                            toPeer: peer,
                            body: row.body,
                            date: TeamDirectMessagesService.parseCreatedAt(row.createdAt) ?? Date()
                        )
                        NotificationCenter.default.post(name: .messageDidRespond, object: nil)
                    }
                } catch {
                    await MainActor.run { draft = text }
                }
            }
            return
        }
        let now = Self.currentTimeString()
        liveMessages.append(ChatMessage(text: text, isOutgoing: true, time: now, receipt: .sent))
        if usesPatientLocalChat {
            chatInbox.applyPatientLocalPreview(threadId: thread.id, preview: text, date: Date())
        }
        draft = ""
    }

    /// Copia la nota de voz a Documents para que no se borre al limpiar el temporal.
    private static func persistLocalVoiceNote(from url: URL) -> URL? {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PatientLocalVoice", isDirectory: true)
        guard let dir else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("\(UUID().uuidString).m4a")
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            return nil
        }
    }

    private func seedPatientLocalWelcomeIfNeeded() {
        guard usesPatientLocalChat, liveMessages.isEmpty else { return }
        let now = Self.currentTimeString()
        liveMessages = [
            ChatMessage(
                text: "Chat de prueba con \(thread.title).\nPuedes enviar texto, fotos y notas de voz (solo en este dispositivo).",
                isOutgoing: false,
                time: now,
                receipt: nil
            )
        ]
    }

    // MARK: - Conversación real del CRM (WhatsApp/Instagram)

    /// Carga inicial + fallback ligero (API sin cursor). Sin poll cada 6 s.
    private func runCrmSessionIfNeeded() async {
        guard thread.kind == .lead else { return }
        await refreshCrmMessages(clearLocal: false)
        // Recuperación: como máximo ~90 s; Realtime CRM no existe en backend.
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 90_000_000_000)
            guard !Task.isCancelled else { break }
            await refreshCrmMessages(clearLocal: false)
        }
    }

    @MainActor
    private func refreshCrmMessages(clearLocal: Bool) async {
        guard let convId = chatInbox.crmConversationIdByThread[thread.id],
              let token = auth.session?.accessToken
        else { return }
        let started = Date()
        guard let rows = try? await CrmChatService.messages(token: token, conversationId: convId, limit: 100)
        else { return }

        let previousIds = crmRows.map(\.id)
        let merged = chatInbox.mergeCachedCrmMessages(rows, for: thread.id)
        let newIds = merged.map(\.id)
        let unchanged = !clearLocal && previousIds == newIds
            && crmRows.last?.textContent == merged.last?.textContent
            && crmRows.last?.createdAt == merged.last?.createdAt

        if unchanged {
            ChatPerfLog.conversation(
                String(format: "skip apply; unchanged in %.2fs", Date().timeIntervalSince(started))
            )
        } else {
            crmRows = merged
            for row in merged {
                guard let editedAt = row.editedAt?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      !editedAt.isEmpty else { continue }
                editedMessageIds.insert(CrmChatService.stableUUID(for: "msg:\(row.id)"))
            }
            ChatPerfLog.conversation(
                String(
                    format: "applied messages=%d in %.2fs",
                    merged.count,
                    Date().timeIntervalSince(started)
                )
            )
        }

        if clearLocal {
            liveMessages.removeAll()
        } else {
            let serverOutgoingTexts = Set(
                merged
                    .filter { !CrmChatService.messageIsFromContact($0.senderType) }
                    .compactMap(\.textContent)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            )
            liveMessages.removeAll { msg in
                guard msg.isOutgoing else { return false }
                if let text = msg.text {
                    return serverOutgoingTexts.contains(text.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                if msg.image != nil {
                    let hasServerImage = merged.contains { row in
                        guard !CrmChatService.messageIsFromContact(row.senderType) else { return false }
                        guard CrmChatService.isImageMessage(row) else { return false }
                        guard let serverDate = CrmChatService.parseISO(row.createdAt) else { return false }
                        return abs(serverDate.timeIntervalSince(msg.sortKey)) < 240
                    }
                    return hasServerImage
                }
                return false
            }
        }
        if let preview = CrmChatService.latestInboxPreview(from: merged) {
            chatInbox.applyCrmLeadPreview(
                threadId: thread.id,
                preview: preview.text,
                date: preview.date
            )
        }
        if chatInbox.activeLeadThreadId == thread.id {
            chatInbox.markThreadAsRead(thread.id)
            await chatInbox.markCrmThreadAsRead(
                threadId: thread.id,
                accessToken: token
            )
        }
    }

    @MainActor
    private func mergeTeamDirectInsert(_ row: TeamDirectMessagesService.Row) {
        guard !moderation.isBlocked(row.senderId) else { return }
        guard !teamDirectRows.contains(where: { $0.id == row.id }) else { return }
        teamDirectRows.append(row)
        teamDirectRows.sort { $0.createdAt < $1.createdAt }
    }

    @MainActor
    private func applyTeamDirectUpdate(_ row: TeamDirectMessagesService.Row) {
        guard let i = teamDirectRows.firstIndex(where: { $0.id == row.id }) else { return }
        teamDirectRows[i] = row
    }

    @MainActor
    private func mergeTeamGroupInsert(_ row: TeamGroupMessagesService.Row) {
        guard !moderation.isBlocked(row.senderId) else { return }
        guard !teamGroupRows.contains(where: { $0.id == row.id }) else { return }
        teamGroupRows.append(row)
        teamGroupRows.sort { $0.createdAt < $1.createdAt }
    }

    private func runTeamGroupSessionIfNeeded() async {
        guard usesTeamGroupServer, let myId = auth.session?.user.id else { return }
        teamGroupLoadError = nil
        if let existing = teamGroupChannel {
            await SupabaseClientProvider.shared.removeChannel(existing)
            await MainActor.run { teamGroupChannel = nil }
        }
        do {
            let rows = try await TeamGroupMessagesService.fetchMessages(client: SupabaseClientProvider.shared)
            await MainActor.run { teamGroupRows = rows }
        } catch {
            await MainActor.run { teamGroupLoadError = error.localizedDescription }
        }

        let client = SupabaseClientProvider.shared
        let channel = client.channel("team-group-thread-\(myId.uuidString.lowercased())")
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: TeamGroupMessagesService.tableName
        )
        do {
            try await channel.subscribeWithError()
        } catch {
            return
        }
        await MainActor.run { teamGroupChannel = channel }
        for await action in inserts {
            guard let row = try? TeamGroupMessagesService.decodeInsert(action) else { continue }
            await MainActor.run {
                mergeTeamGroupInsert(row)
            }
        }
    }

    private func runTeamDirectSessionIfNeeded() async {
        guard usesTeamDirectServer, let peer = thread.peerUserId, let myId = auth.session?.user.id else { return }
        teamDirectLoadError = nil
        if let existing = teamDirectChannel {
            await SupabaseClientProvider.shared.removeChannel(existing)
            await MainActor.run { teamDirectChannel = nil }
        }
        do {
            try await TeamDirectMessagesService.markThreadRead(
                peerUserId: peer,
                client: SupabaseClientProvider.shared
            )
            let rows = try await TeamDirectMessagesService.fetchConversation(
                myUserId: myId,
                peerUserId: peer,
                client: SupabaseClientProvider.shared
            )
            await MainActor.run { teamDirectRows = rows }
        } catch {
            await MainActor.run { teamDirectLoadError = error.localizedDescription }
        }

        let client = SupabaseClientProvider.shared
        let channel = client.channel("dm-thread-\(myId.uuidString.lowercased())-\(peer.uuidString.lowercased())")
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: TeamDirectMessagesService.tableName
        )
        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: TeamDirectMessagesService.tableName
        )
        do {
            try await channel.subscribeWithError()
        } catch {
            return
        }
        await MainActor.run { teamDirectChannel = channel }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await action in inserts {
                    guard let row = try? TeamDirectMessagesService.decodeInsert(action) else { continue }
                    let involves = (row.senderId == peer && row.recipientId == myId)
                        || (row.senderId == myId && row.recipientId == peer)
                    guard involves else { continue }
                    await MainActor.run {
                        mergeTeamDirectInsert(row)
                    }
                }
            }
            group.addTask {
                for await action in updates {
                    guard let row = try? TeamDirectMessagesService.decodeUpdate(action) else { continue }
                    let involves = (row.senderId == peer && row.recipientId == myId)
                        || (row.senderId == myId && row.recipientId == peer)
                    guard involves else { continue }
                    await MainActor.run {
                        applyTeamDirectUpdate(row)
                    }
                }
            }
        }
    }

    private static func chatMessage(from row: TeamDirectMessagesService.Row, myUserId: UUID) -> ChatMessage {
        let outgoing = row.senderId == myUserId
        let receipt: OutgoingReceipt? = outgoing ? (row.readAt != nil ? .read : .sent) : nil
        let time = formatChatTime(iso: row.createdAt)
        let sortKey = TeamDirectMessagesService.parseCreatedAt(row.createdAt) ?? Date()
        if let vPath = TeamDirectVoiceStorage.storagePath(fromMessageBody: row.body) {
            return ChatMessage(
                id: row.id,
                voiceStoragePath: vPath,
                isOutgoing: outgoing,
                time: time,
                receipt: receipt,
                sortKey: sortKey,
                senderUserId: row.senderId
            )
        }
        return ChatMessage(
            id: row.id,
            text: row.body,
            isOutgoing: outgoing,
            time: time,
            receipt: receipt,
            sortKey: sortKey,
            senderUserId: row.senderId
        )
    }

    private static func chatMessageGroup(
        from row: TeamGroupMessagesService.Row,
        myUserId: UUID,
        directory: [CommunityProfilesService.DirectoryRow]
    ) -> ChatMessage {
        let outgoing = row.senderId == myUserId
        let displayText: String
        if outgoing {
            displayText = row.body
        } else {
            let name = directory.first(where: { $0.userId == row.senderId })?.resolvedDisplayName ?? "Usuario"
            displayText = "\(name): \(ContentModerationFilter.sanitizeForDisplay(row.body))"
        }
        let time = formatChatTime(iso: row.createdAt)
        let sortKey = TeamGroupMessagesService.parseCreatedAt(row.createdAt) ?? Date()
        return ChatMessage(
            id: row.id,
            text: displayText,
            isOutgoing: outgoing,
            time: time,
            receipt: outgoing ? .sent : nil,
            sortKey: sortKey,
            senderUserId: row.senderId
        )
    }

    private var primaryModerationTarget: ModerationTarget? {
        if usesTeamDirectServer, let peer = thread.peerUserId {
            let name = communityVM.directory.first(where: { $0.userId == peer })?.resolvedDisplayName ?? thread.title
            return moderationTarget(
                userId: peer,
                contentType: .teamDirectMessage,
                contentId: teamDirectRows.last?.id,
                contentPreview: teamDirectRows.last?.body,
                userName: name
            )
        }
        if usesTeamGroupServer,
           let last = teamGroupRows.last(where: { $0.senderId != auth.session?.user.id })
        {
            let name = communityVM.directory.first(where: { $0.userId == last.senderId })?.resolvedDisplayName ?? "Usuario"
            return moderationTarget(
                userId: last.senderId,
                contentType: .teamGroupMessage,
                contentId: last.id,
                contentPreview: last.body,
                userName: name
            )
        }
        return nil
    }

    private func moderationTarget(
        userId: UUID,
        contentType: UserModerationService.ContentType,
        contentId: UUID?,
        contentPreview: String?,
        userName: String? = nil
    ) -> ModerationTarget {
        let resolvedName = userName
            ?? communityVM.directory.first(where: { $0.userId == userId })?.resolvedDisplayName
            ?? thread.title
        return ModerationTarget(
            userId: userId,
            userName: resolvedName,
            contentType: contentType,
            contentId: contentId,
            contentPreview: contentPreview
        )
    }

    @MainActor
    private func blockPrimaryTarget() async {
        guard let target = reportTarget ?? primaryModerationTarget else { return }
        let ok = await moderation.blockUser(
            target.userId,
            autoReportReason: "Bloqueo de usuario desde conversación",
            contentType: target.contentType,
            contentId: target.contentId,
            contentPreview: target.contentPreview
        )
        moderationAlertMessage = ok ? moderation.lastSuccessMessage : moderation.lastErrorMessage
        showModerationAlert = moderationAlertMessage != nil
        reportTarget = nil
        if usesTeamDirectServer {
            teamDirectRows.removeAll { moderation.isBlocked($0.senderId) }
        }
        if usesTeamGroupServer {
            teamGroupRows.removeAll { moderation.isBlocked($0.senderId) }
        }
        chatInbox.refreshTeamThreadsFromSnapshot(blockedUserIds: moderation.blockedUserIds)
    }

    private static func formatChatTime(iso: String) -> String {
        guard let d = TeamDirectMessagesService.parseCreatedAt(iso) else { return String(iso.prefix(8)) }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private func dismissComposerKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    /// Baja al final del hilo (mensajes, tareas IA y borrador en vivo).
    private func scrollChatToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        let anchorId = chatBottomAnchorId
        let scroll = {
            if animated {
                withAnimation(.easeOut(duration: 0.28)) {
                    proxy.scrollTo(anchorId, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(anchorId, anchor: .bottom)
            }
        }
        DispatchQueue.main.async {
            scroll()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                if animated {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(anchorId, anchor: .bottom)
                    }
                } else {
                    proxy.scrollTo(anchorId, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Helpers

    private static func currentTimeString() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }

    // MARK: - Mock

    private static func mockMessages(for thread: ChatThread) -> [ChatMessage] {
        if thread.kind == .teamGroup {
            return [
                ChatMessage(text: "Aquí hablamos todo el equipo del directorio.", isOutgoing: false, time: "8:40"),
                ChatMessage(text: "Perfecto, dejamos avisos y turnos en este grupo.", isOutgoing: true, time: "8:42", receipt: .read),
                ChatMessage(text: "Cuando alguien suba ubicación, lo vemos en el mapa de Inicio.", isOutgoing: false, time: "8:45")
            ]
        }
        if thread.kind == .teamDirect {
            let name = thread.title
            return [
                ChatMessage(text: "Hola, te escribo por el chat interno del equipo.", isOutgoing: false, time: "9:05"),
                ChatMessage(text: "Hola \(name.split(separator: " ").first.map(String.init) ?? name), ¿nos vemos más tarde?", isOutgoing: true, time: "9:08", receipt: .read),
                ChatMessage(text: "Sí, sin problema. Cualquier cosa me escribes aquí.", isOutgoing: false, time: "9:09")
            ]
        }
        switch thread.id.uuidString {
        case "10000000-0000-0000-0000-000000000001":
            return [
                ChatMessage(text: "Hola, quiero NAD + y Energy Focus del live.", isOutgoing: false, time: "12:18"),
                ChatMessage(text: "Perfecto, te paso el enlace de pago por $116.", isOutgoing: true, time: "12:22", receipt: .read),
                ChatMessage(text: "Pedido: NAD + y Energy Focus — $116", isOutgoing: false, time: "12:30")
            ]
        case "10000000-0000-0000-0000-000000000002":
            return [
                ChatMessage(text: "¿El Recovery Sleep sigue en stock?", isOutgoing: false, time: "Ayer 17:40"),
                ChatMessage(text: "Sí, envío hoy mismo. Son $67.", isOutgoing: true, time: "Ayer 17:55", receipt: .read),
                ChatMessage(text: "Traders Recovery Sleep & Wellness — $67", isOutgoing: false, time: "Ayer 18:10")
            ]
        case "10000000-0000-0000-0000-000000000003":
            return [
                ChatMessage(text: "Hola, ¿cuánto tarda el envío de 3 productos?", isOutgoing: false, time: "10:02"),
                ChatMessage(text: "Consulta envío de 3 productos — $132.40", isOutgoing: false, time: "10:15"),
                ChatMessage(text: "Entre 3 y 5 días laborables en EE. UU.", isOutgoing: true, time: "10:18", receipt: .read)
            ]
        case "10000000-0000-0000-0000-000000000004":
            return [
                ChatMessage(text: "Acabo de comprar NAD + en el directo.", isOutgoing: false, time: "08:55"),
                ChatMessage(text: "Compra NAD + completada — $49", isOutgoing: false, time: "09:02"),
                ChatMessage(text: "¡Gracias! Tu comisión ya aparece en el panel.", isOutgoing: true, time: "09:05", receipt: .read)
            ]
        case "10000000-0000-0000-0000-000000000005":
            return [
                ChatMessage(text: "Me interesa Energy Focus, ¿cómo pago?", isOutgoing: false, time: "Ayer 18:20"),
                ChatMessage(text: "Te envío el checkout de TikTok Shop.", isOutgoing: true, time: "Ayer 18:28", receipt: .read),
                ChatMessage(text: "Pendiente pago Energy Focus — $67", isOutgoing: false, time: "Ayer 18:40")
            ]
        case "10000000-0000-0000-0000-000000000006":
            return [
                ChatMessage(text: "¿Tienen stock de NAD+ para envío hoy?", isOutgoing: false, time: "4:15"),
                ChatMessage(text: "Sí, quedan unidades. ¿Cuántas necesitas?", isOutgoing: true, time: "4:20", receipt: .read),
                ChatMessage(text: "Dos frascos, por favor.", isOutgoing: false, time: "4:23")
            ]
        case "10000000-0000-0000-0000-000000000007":
            return [
                ChatMessage(text: "Hola, bundle Recovery + NAD con mi enlace.", isOutgoing: false, time: "mar 11:02"),
                ChatMessage(text: "Bundle Recovery + NAD — comisión afiliado", isOutgoing: false, time: "mar 11:08"),
                ChatMessage(text: "Listo, ya está registrado en tu panel.", isOutgoing: true, time: "mar 11:15", receipt: .read)
            ]
        case "10000000-0000-0000-0000-000000000008":
            return [
                ChatMessage(text: "Compré 2 Energy Focus en el live de anoche.", isOutgoing: false, time: "lun 9:05"),
                ChatMessage(text: "Pedido confirmado: Energy Focus x2", isOutgoing: false, time: "lun 9:12"),
                ChatMessage(text: "Genial, comisión actualizada.", isOutgoing: true, time: "lun 9:20", receipt: .read)
            ]
        default:
            return [
                ChatMessage(text: "Hola, ¿en qué podemos ayudarte?", isOutgoing: false, time: "10:12"),
                ChatMessage(text: "Gracias, te escribo desde GControl.", isOutgoing: true, time: "10:18", receipt: .read)
            ]
        }
    }
}

// MARK: - Lock hint (slide up)

private struct ChatVoiceLockHint: View {
    var progress: CGFloat
    var isArmed: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: isArmed ? "lock.fill" : "lock")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isArmed ? GrooChatTheme.telegramBlue : Color.black.opacity(0.55))
                .symbolEffect(.bounce, value: isArmed)

            Image(systemName: "chevron.up")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.35 + 0.4 * progress))
                .offset(y: isArmed ? -2 : (1 - progress) * 3)
        }
        .frame(width: 40, height: 72)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(isArmed ? 0.96 : 0.88))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isArmed ? GrooChatTheme.telegramBlue.opacity(0.55) : Color.white.opacity(0.9),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        }
        .scaleEffect(0.92 + 0.12 * progress)
        .opacity(0.55 + 0.45 * Double(progress == 0 ? 0.7 : progress))
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isArmed)
        .animation(.interactiveSpring(duration: 0.18), value: progress)
    }
}

// MARK: - Slide to cancel (RecorderUI)

private struct ChatSlideToCancelText: View {
    var text: String = "Desliza para cancelar"
    @State private var animate = false

    var body: some View {
        viewContent
            .foregroundStyle(Color.black.opacity(0.35))
            .overlay {
                viewContent
                    .foregroundStyle(Color.black.opacity(0.75))
                    .mask {
                        GeometryReader { geo in
                            Rectangle()
                                .frame(width: 15, height: geo.size.width)
                                .blur(radius: 5)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .offset(x: animate ? -geo.size.width * 1.1 : 30)
                        }
                    }
            }
            .compositingGroup()
            .onAppear {
                guard !animate else { return }
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
    }

    private var viewContent: some View {
        HStack(spacing: 5) {
            Image(systemName: "chevron.left")
                .font(.caption)
            Text(text)
                .font(.system(size: 14, weight: .medium))
        }
    }
}

// MARK: - Clip / mic → basura al cancelar (RecorderUI)

private struct ChatComposerAttachControl: View {
    var isRecording: Bool
    var isLockedRecording: Bool = false
    @Binding var playDiscardAnimation: Bool
    var action: () -> Void

    @State private var keyFrameTrigger = false
    @State private var isTrashOpen = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLockedRecording && !playDiscardAnimation {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(0.9))
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                } else if isRecording || playDiscardAnimation {
                    Image(systemName: "mic")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.7))
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                        .keyframeAnimator(initialValue: KeyFrame(), trigger: keyFrameTrigger) { content, frame in
                            content
                                .scaleEffect(frame.scale, anchor: .bottom)
                                .rotationEffect(.degrees(frame.rotation))
                                .offset(y: frame.offset)
                                .opacity(frame.opacity)
                        } keyframes: { _ in
                            CubicKeyframe(KeyFrame(offset: -50, rotation: 360), duration: 0.25)
                            CubicKeyframe(KeyFrame(scale: 0.5, offset: 0, rotation: 360), duration: 0.25)
                            CubicKeyframe(KeyFrame(opacity: 0, scale: 0.5, offset: 0, rotation: 360), duration: 0.1)
                        }
                } else {
                    Image(systemName: "paperclip")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.65))
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }

                trashCan(isTrashOpen)
                    .keyframeAnimator(initialValue: KeyFrame(opacity: 0, scale: 0.5), trigger: keyFrameTrigger) { content, frame in
                        content
                            .scaleEffect(frame.scale)
                            .opacity(frame.opacity)
                    } keyframes: { _ in
                        CubicKeyframe(KeyFrame(scale: 1), duration: 0.2)
                        CubicKeyframe(KeyFrame(scale: 1), duration: 0.5)
                        CubicKeyframe(KeyFrame(opacity: 0, scale: 0.5), duration: 0.2)
                    }
            }
            .frame(width: 40, height: 40)
            .background { GrooChatTheme.glassCircleBackground() }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting((!isRecording || isLockedRecording) && !playDiscardAnimation)
        .animation(.easeInOut(duration: 0.3), value: isRecording)
        .animation(.easeInOut(duration: 0.3), value: isLockedRecording)
        .animation(.easeInOut(duration: 0.3), value: playDiscardAnimation)
        .onChange(of: playDiscardAnimation) { _, newValue in
            guard newValue else { return }
            keyFrameTrigger.toggle()
            Task { @MainActor in
                isTrashOpen = true
                try? await Task.sleep(for: .seconds(0.5))
                isTrashOpen = false
                try? await Task.sleep(for: .seconds(0.2))
                playDiscardAnimation = false
            }
        }
    }

    @ViewBuilder
    private func trashCan(_ isOpen: Bool) -> some View {
        VStack(spacing: 2) {
            VStack(spacing: 0) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 10,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 10
                )
                .frame(width: 15, height: 6)

                Capsule()
                    .frame(height: 4)
            }
            .compositingGroup()
            .rotationEffect(.degrees(isOpen ? -90 : 0), anchor: .bottomLeading)
            .offset(y: isOpen ? 10 : 0)

            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 5,
                bottomTrailingRadius: 5,
                topTrailingRadius: 0
            )
            .frame(width: 20, height: 20)
        }
        .frame(width: 25)
        .foregroundStyle(Color.black.opacity(0.45))
        .compositingGroup()
        .scaleEffect(0.8)
        .animation(.easeInOut(duration: 0.3), value: isOpen)
    }

    @Animatable
    struct KeyFrame {
        var opacity: CGFloat = 1
        var scale: CGFloat = 1
        var offset: CGFloat = 0
        var rotation: CGFloat = 0
    }
}

// MARK: - Mic nota de voz (toca = grabar / toca otra vez = enviar)

private struct VoiceNoteMicTapControl: View {
    var isRecording: Bool
    var isBusy: Bool = false
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Group {
                if isBusy {
                    ProgressView()
                        .tint(Color.black.opacity(0.55))
                        .scaleEffect(0.75)
                } else {
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isRecording ? Color.red.opacity(0.92) : Color.black.opacity(0.7))
                }
            }
            .frame(width: 40, height: 40)
            .background { GrooChatTheme.glassCircleBackground() }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.65 : 1)
        .accessibilityLabel(isBusy ? "Enviando audio" : (isRecording ? "Detener y enviar audio" : "Grabar audio"))
        .accessibilityHint(isBusy ? "Espera a que termine el envío" : (isRecording ? "Toca para detener y enviar el audio" : "Toca para empezar a grabar"))
    }
}

// MARK: - Mic DM equipo (legacy: mantén pulsado)

private struct TeamDirectMicGestureControl: View {
    var isDictating: Bool
    var isRecordingVoice: Bool
    var onStopDictation: () -> Void
    var onShortTap: () -> Void
    var onHoldBegan: () -> Void
    var onHoldEnded: () -> Void

    @State private var pressToken = 0
    @State private var fingerDown = false

    private let holdNanoseconds: UInt64 = 450_000_000

    var body: some View {
        ZStack {
            DashboardChromeHeaderCircleBackground(size: AppChromeHeaderMetrics.circleButtonSize)
            Image(systemName: isRecordingVoice ? "mic.fill" : (isDictating ? "stop.fill" : "mic.fill"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(
                    isRecordingVoice ? Color.red.opacity(0.92) : Color.white.opacity(0.95)
                )
        }
        .contentShape(Circle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if isDictating { return }
                    if !fingerDown {
                        fingerDown = true
                        pressToken &+= 1
                        let token = pressToken
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: holdNanoseconds)
                            guard !Task.isCancelled, token == pressToken, fingerDown else { return }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onHoldBegan()
                        }
                    }
                }
                .onEnded { _ in
                    if isRecordingVoice {
                        pressToken &+= 1
                        fingerDown = false
                        onHoldEnded()
                        return
                    }
                    if isDictating {
                        fingerDown = false
                        pressToken &+= 1
                        onStopDictation()
                        return
                    }
                    pressToken &+= 1
                    fingerDown = false
                    onShortTap()
                }
        )
        .accessibilityLabel(accessibilityTitle)
        .accessibilityHint("Mantén pulsado para grabar y enviar una nota de voz. Toca para dictado en vivo.")
    }

    private var accessibilityTitle: String {
        if isRecordingVoice { return "Grabando nota de voz" }
        if isDictating { return "Detener dictado" }
        return "Dictar o nota de voz"
    }
}

// MARK: - Burbuja nota de voz (Storage + CRM remoto)

private enum VoiceAudioSource: Equatable {
    case supabase(path: String)
    case remote(url: URL, accessToken: String?)

    var taskID: String {
        switch self {
        case .supabase(let path): return "sb:\(path)"
        case .remote(let url, let token): return "rm:\(url.absoluteString)|\(token ?? "")"
        }
    }

    var localFileURL: URL? {
        switch self {
        case .remote(let url, _) where url.isFileURL:
            return url
        default:
            return nil
        }
    }

    var fileExtension: String {
        switch self {
        case .supabase: return "m4a"
        case .remote(let url, _):
            let pathExt = url.pathExtension.lowercased()
            if ["m4a", "mp4", "mp3", "aac", "wav", "ogg", "opus", "webm", "caf"].contains(pathExt) {
                return pathExt == "opus" ? "ogg" : pathExt
            }
            let raw = url.absoluteString.lowercased()
            if raw.contains("audio/mp4") || raw.contains(".m4a") || raw.contains("mpeg4") { return "m4a" }
            if raw.contains("audio/mpeg") || raw.contains(".mp3") { return "mp3" }
            if raw.contains("audio/ogg") || raw.contains("opus") || raw.contains(".ogg") { return "ogg" }
            if raw.contains("audio/webm") || raw.contains(".webm") { return "webm" }
            if url.scheme?.lowercased() == "data" {
                if raw.contains("ogg") || raw.contains("opus") { return "ogg" }
                if raw.contains("mpeg") || raw.contains("mp3") { return "mp3" }
                if raw.contains("mp4") || raw.contains("m4a") || raw.contains("aac") { return "m4a" }
            }
            // Instagram / Meta CDN suelen servir ogg/opus sin extensión clara.
            return "ogg"
        }
    }

}

private struct VoiceNoteBubbleView: View {
    let source: VoiceAudioSource
    let messageId: String
    let speakerTitle: String
    let chatSubtitle: String
    let threadId: UUID
    let isOutgoing: Bool
    let time: String
    let receipt: OutgoingReceipt?
    let maxBubbleWidth: CGFloat

    /// No observar el coordinator entero: el reloj va por TimelineView; play/pause via estado local + ticks pausables.
    private var playback: ChatVoicePlaybackCoordinator { ChatVoicePlaybackCoordinator.shared }
    @State private var isPlayLoading = false
    @State private var chromePlaying = false
    @State private var chromeActive = false
    @State private var isPrefetching = false
    @State private var loadFailed = false
    @State private var cachedAudioData: Data?
    @State private var waveformBars: [CGFloat] = []
    @State private var audioDuration: TimeInterval = 0
    @State private var scrubProgress: CGFloat = 0
    @State private var isScrubbing = false
    @State private var scrubberFileURL: URL?

    private var isThisPlaying: Bool { chromePlaying }
    private var isThisActive: Bool { chromeActive }

    private let incomingBubbleFill = Color.white.opacity(0.92)
    private let incomingMeta = Color.black.opacity(0.38)
    private let outgoingMeta = Color.black.opacity(0.38)
    private let bubblePadH: CGFloat = 12
    private let bubblePadV: CGFloat = 10
    private let bubbleCorner: CGFloat = 18
    private let waveformStripHeight: CGFloat = 34
    private let playButtonSize: CGFloat = 40
    /// Ancho mínimo / máximo de burbuja (corto = estrecho estilo WhatsApp/Telegram).
    private let minBubbleWidth: CGFloat = 148
    /// Por debajo de esto: duración arriba, hora + ✓ debajo (no al lado).
    private let compactLayoutMaxDuration: TimeInterval = 5.5
    /// Segundos a partir de los cuales la burbuja llega al ancho máximo.
    private let durationForMaxWidth: TimeInterval = 22

    /// Duración efectiva (prefetch o player global).
    private var effectiveDuration: TimeInterval {
        if isThisActive, playback.duration > 0.2 { return playback.duration }
        return max(audioDuration, 0)
    }

    /// Ancho según duración: ~2–3 s estrecho, ~17–22 s cerca del máximo.
    private var adaptiveBubbleWidth: CGFloat {
        let maxW = max(minBubbleWidth, maxBubbleWidth)
        let duration = max(effectiveDuration > 0.2 ? effectiveDuration : 1.2, 1.0)
        let t = min(1, CGFloat(duration / durationForMaxWidth))
        let eased = pow(t, 0.72)
        return minBubbleWidth + (maxW - minBubbleWidth) * eased
    }

    /// Nº de barras proporcionales a la duración (y al ancho útil del waveform).
    private var waveformBarCount: Int {
        let duration = max(effectiveDuration > 0.2 ? effectiveDuration : 2.0, 1.0)
        let contentW = max(48, adaptiveBubbleWidth - bubblePadH * 2 - playButtonSize - 10)
        let fitCount = Int(floor((contentW + 2.2) / 4.4))
        let byDuration = Int(8 + min(40, duration * 2.2))
        return min(max(10, min(fitCount, byDuration)), 48)
    }

    private var usesCompactMetaLayout: Bool {
        let duration = effectiveDuration > 0.2 ? effectiveDuration : 1.0
        return duration < compactLayoutMaxDuration
    }

    private var canUseNativeScrubber: Bool {
        scrubberFileURL != nil
            && ["m4a", "mp4", "wav", "caf", "aiff", "aif"].contains(source.fileExtension)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: bubbleCorner, style: .continuous)
        HStack(alignment: .center, spacing: 10) {
            Button {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
                togglePlayback()
            } label: {
                playCircleButton
            }
            .buttonStyle(.plain)
            .disabled(isPlayLoading)

            VStack(alignment: .leading, spacing: usesCompactMetaLayout ? 4 : 6) {
                playbackWaveform
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()

                if usesCompactMetaLayout {
                    // Corto: 0:02 → debajo hora + checks (como referencia WhatsApp).
                    VStack(alignment: .leading, spacing: 2) {
                        durationLabel
                        bubbleMetaRow
                    }
                } else {
                    HStack(alignment: .center, spacing: 8) {
                        durationLabel
                        Spacer(minLength: 4)
                        bubbleMetaRow
                    }
                }

                if loadFailed && waveformBars.isEmpty && scrubberFileURL == nil {
                    Text("No se pudo cargar el audio")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.orange.opacity(0.95))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .padding(.horizontal, bubblePadH)
        .padding(.vertical, bubblePadV)
        .frame(width: adaptiveBubbleWidth, alignment: isOutgoing ? .trailing : .leading)
        .background {
            if isOutgoing {
                shape.fill(GrooChatTheme.outgoingBubble)
            } else {
                shape.fill(incomingBubbleFill)
            }
        }
        .clipShape(shape)
        .animation(.easeInOut(duration: 0.18), value: adaptiveBubbleWidth)
        .task(id: source.taskID) {
            await prefetchWaveform()
        }
        .onAppear { syncChromeFromPlayback() }
        // Solo publishers reales (no currentTime): evita rebuild a 30 Hz.
        .onReceive(playback.$isPlaying) { _ in syncChromeFromPlayback() }
        .onReceive(playback.$session) { _ in syncChromeFromPlayback() }
        .onReceive(playback.$duration) { _ in syncChromeFromPlayback() }
        .onChange(of: chromeActive) { _, active in
            if !active {
                scrubProgress = 0
            }
        }
    }

    private func syncChromeFromPlayback() {
        let active = playback.isActiveItem(id: messageId)
        let playing = playback.isPlayingItem(id: messageId)
        if chromeActive != active { chromeActive = active }
        if chromePlaying != playing { chromePlaying = playing }
        if active, playback.duration > 0.2, abs(audioDuration - playback.duration) > 0.05 {
            audioDuration = playback.duration
        }
    }

    private var playCircleButton: some View {
        ZStack {
            Circle()
                .fill(GrooChatTheme.telegramBlue)
                .frame(width: playButtonSize, height: playButtonSize)

            if isPlayLoading {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.72)
            } else {
                Image(systemName: chromePlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: chromePlaying ? 15 : 14, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: chromePlaying ? 0 : 1.5)
            }
        }
        .opacity(isPlayLoading ? 0.85 : 1)
    }

    private var displayedScrubProgress: CGFloat {
        if isScrubbing { return scrubProgress }
        if isThisActive { return CGFloat(playback.progress(for: messageId)) }
        return scrubProgress
    }

    @ViewBuilder
    private var playbackWaveform: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isThisPlaying || isScrubbing)) { _ in
            let liveProgress = displayedScrubProgress
            if canUseNativeScrubber, let scrubURL = scrubberFileURL {
                WaveformScrubber(
                    config: .init(
                        spacing: 2.2,
                        shapeWidth: 2.2,
                        activeTint: GrooChatTheme.telegramBlue,
                        inActiveTint: Color.black.opacity(isOutgoing ? 0.18 : 0.22)
                    ),
                    url: scrubURL,
                    progress: Binding(
                        get: { isScrubbing ? scrubProgress : liveProgress },
                        set: { scrubProgress = $0 }
                    ),
                    info: { info in
                        if info.duration > 0.2 {
                            audioDuration = info.duration
                        }
                    },
                    onGestureActive: { active in
                        if active {
                            UIApplication.shared.sendAction(
                                #selector(UIResponder.resignFirstResponder),
                                to: nil, from: nil, for: nil
                            )
                        }
                        isScrubbing = active
                        if !active {
                            seekToProgress(scrubProgress)
                        }
                    }
                )
                .frame(maxWidth: .infinity)
                .frame(height: waveformStripHeight)
                .clipped()
            } else {
                voiceWaveformStrip(progress: liveProgress)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: waveformStripHeight)
        .clipped()
    }

    private func voiceWaveformStrip(progress: CGFloat) -> some View {
        VoiceMessageWaveformStrip(
            bars: waveformBars,
            progress: progress,
            isLoading: isPrefetching && waveformBars.isEmpty,
            accentColor: GrooChatTheme.telegramBlue,
            inactiveColor: Color.black.opacity(isOutgoing ? 0.18 : 0.22),
            stripHeight: waveformStripHeight,
            onSeek: { fraction in
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
                scrubProgress = fraction
                if isScrubbing { return }
                seekToProgress(fraction)
            },
            onSeekActive: { active in
                let wasActive = isScrubbing
                isScrubbing = active
                if wasActive, !active {
                    seekToProgress(scrubProgress)
                }
            }
        )
        .frame(maxWidth: .infinity)
        .clipped()
    }

    @MainActor
    private func seekToProgress(_ fraction: CGFloat) {
        if isThisActive {
            playback.seek(toFraction: Double(fraction))
            return
        }
        guard let data = cachedAudioData else { return }
        scrubProgress = fraction
        playback.toggle(
            id: messageId,
            title: speakerTitle,
            subtitle: chatSubtitle,
            threadId: threadId,
            data: data,
            fileExtension: source.fileExtension,
            knownDuration: audioDuration
        )
        playback.seek(toFraction: Double(fraction))
    }

    private var currentPlaybackTime: TimeInterval {
        isThisActive ? playback.currentTime(for: messageId) : 0
    }

    @ViewBuilder
    private var durationLabel: some View {
        Group {
            if isThisActive {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isThisPlaying)) { _ in
                    Text(VoiceMessageWaveformExtractor.formatDuration(currentPlaybackTime))
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(incomingMeta)
                }
            } else {
                Text(VoiceMessageWaveformExtractor.formatDuration(effectiveDuration > 0.2 ? effectiveDuration : audioDuration))
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(incomingMeta)
            }
        }
    }

    @ViewBuilder
    private var bubbleMetaRow: some View {
        HStack(spacing: 3) {
            Text(time)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(isOutgoing ? outgoingMeta : incomingMeta)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if isOutgoing, let receipt {
                voiceReceiptMarks(receipt)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func voiceReceiptMarks(_ receipt: OutgoingReceipt) -> some View {
        switch receipt {
        case .sent:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(outgoingMeta)
        case .delivered:
            HStack(spacing: -5) {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(Color.black.opacity(0.28))
        case .read:
            HStack(spacing: -5) {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(GrooChatTheme.telegramBlue)
        }
    }

    private func prefetchWaveform() async {
        await MainActor.run {
            isPrefetching = true
            loadFailed = false
            waveformBars = []
            cachedAudioData = nil
            audioDuration = 0
        }
        let src = source
        let ext = src.fileExtension
        do {
            let data = try await loadAudioData(from: src)
            let dur = VoiceMessageWaveformExtractor.durationSeconds(ofAudioData: data, fileExtension: ext) ?? 0
            // Extraer con densidad alta; la UI reamplea al ancho real del contenedor.
            let barN = min(48, max(16, Int(8 + min(40, max(dur, 1.5) * 2.2))))
            let bars = await Task.detached(priority: .userInitiated) {
                VoiceMessageWaveformExtractor.waveformBars(
                    fromAudioData: data,
                    fileExtension: ext,
                    barCount: barN
                )
            }.value
            let scrubURL = await MainActor.run {
                prepareScrubberFile(from: data, fileExtension: ext)
            }
            await MainActor.run {
                cachedAudioData = data
                waveformBars = bars
                audioDuration = dur > 0 ? dur : 0
                scrubberFileURL = scrubURL ?? source.localFileURL
                isPrefetching = false
                loadFailed = false
            }
        } catch {
            await MainActor.run {
                isPrefetching = false
                loadFailed = true
                scrubberFileURL = source.localFileURL
            }
        }
    }

    private func loadAudioData(from source: VoiceAudioSource) async throws -> Data {
        switch source {
        case .supabase(let path):
            return try await TeamDirectVoiceStorage.download(
                path: path,
                client: SupabaseClientProvider.shared
            )
        case .remote(let url, let token):
            if url.isFileURL {
                return try Data(contentsOf: url)
            }
            return try await CrmAudioLoader.download(url: url, accessToken: token)
        }
    }

    private func prepareScrubberFile(from data: Data, fileExtension: String) -> URL? {
        if let local = source.localFileURL { return local }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceScrub", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(source.taskID.hashValue).\(fileExtension)")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func togglePlayback() {
        loadFailed = false
        if let data = cachedAudioData {
            playback.toggle(
                id: messageId,
                title: speakerTitle,
                subtitle: chatSubtitle,
                threadId: threadId,
                data: data,
                fileExtension: source.fileExtension,
                knownDuration: audioDuration
            )
            return
        }
        isPlayLoading = true
        let src = source
        Task {
            do {
                let data = try await loadAudioData(from: src)
                await MainActor.run {
                    cachedAudioData = data
                    waveformBars = VoiceMessageWaveformExtractor.waveformBars(
                        fromAudioData: data,
                        fileExtension: src.fileExtension,
                        barCount: waveformBarCount
                    )
                    let dur = VoiceMessageWaveformExtractor.durationSeconds(
                        ofAudioData: data,
                        fileExtension: src.fileExtension
                    ) ?? 0
                    if dur > 0.2 { audioDuration = dur }
                    if scrubberFileURL == nil {
                        scrubberFileURL = prepareScrubberFile(from: data, fileExtension: src.fileExtension)
                            ?? src.localFileURL
                    }
                    isPlayLoading = false
                    playback.toggle(
                        id: messageId,
                        title: speakerTitle,
                        subtitle: chatSubtitle,
                        threadId: threadId,
                        data: data,
                        fileExtension: src.fileExtension,
                        knownDuration: audioDuration
                    )
                }
            } catch {
                await MainActor.run {
                    isPlayLoading = false
                    loadFailed = true
                }
            }
        }
    }
}

// MARK: - Campo multilínea con scroll (UITextView)

/// Crece con el texto hasta `maxComposerHeight`; después activa scroll interno.
private final class ComposerSizingTextView: UITextView {
    var maxComposerHeight: CGFloat = 148
    var centerVerticallyWhenSingleLine = true
    var onMeasuredHeightChange: ((CGFloat) -> Void)?
    private var lastFittingWidth: CGFloat = 0
    private var lastReportedHeight: CGFloat = -1

    private var fittingWidth: CGFloat {
        if bounds.width > 2 { return bounds.width }
        return max(120, UIScreen.main.bounds.width - 120)
    }

    private var rawLineHeight: CGFloat {
        ceil(font?.lineHeight ?? 20)
    }

    func refreshVerticalInsets(forText text: String) {
        let isMultiline = text.contains(where: \.isNewline) || text.count > 32
        if centerVerticallyWhenSingleLine, !isMultiline {
            let target = CGFloat(40)
            let pad = max(0, floor((target - rawLineHeight) / 2))
            textContainerInset = UIEdgeInsets(top: pad, left: 0, bottom: pad, right: 0)
        } else {
            textContainerInset = UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        }
    }

    private var singleLineHeight: CGFloat {
        rawLineHeight + textContainerInset.top + textContainerInset.bottom
    }

    /// Altura natural del contenido (sin tope).
    func unconstrainedContentHeight() -> CGFloat {
        let str = text ?? ""
        refreshVerticalInsets(forText: str)
        let minH = singleLineHeight
        if str.isEmpty { return minH }

        let width = max(fittingWidth, 40)
        let insetW = textContainerInset.left + textContainerInset.right
        let textW = max(width - insetW, 40)
        textContainer.size = CGSize(width: textW, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        let h = ceil(used.height + textContainerInset.top + textContainerInset.bottom)
        return max(h, minH)
    }

    /// Publica altura clampada y activa scroll si el texto supera el tope.
    func publishMeasuredHeight(scrollToCaret: Bool = false) {
        let natural = unconstrainedContentHeight()
        let clamped = min(max(natural, singleLineHeight), maxComposerHeight)
        let needsScroll = natural > maxComposerHeight + 0.5
        if isScrollEnabled != needsScroll {
            isScrollEnabled = needsScroll
        }
        showsVerticalScrollIndicator = needsScroll
        if abs(clamped - lastReportedHeight) > 0.5 {
            lastReportedHeight = clamped
            onMeasuredHeightChange?(clamped)
        }
        if scrollToCaret || needsScroll {
            scrollToVisibleCaretIfNeeded()
        }
    }

    private func scrollToVisibleCaretIfNeeded() {
        guard isScrollEnabled else { return }
        let range = selectedRange
        guard range.location != NSNotFound else { return }
        DispatchQueue.main.async { [weak self] in
            self?.scrollRangeToVisible(range)
        }
    }

    override var intrinsicContentSize: CGSize {
        let h = min(unconstrainedContentHeight(), maxComposerHeight)
        return CGSize(width: UIView.noIntrinsicMetric, height: h)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let insetW = textContainerInset.left + textContainerInset.right
        let textW = max(bounds.width - insetW, 1)
        if abs(textContainer.size.width - textW) > 0.5 {
            textContainer.size = CGSize(width: textW, height: .greatestFiniteMagnitude)
        }
        let w = bounds.width
        if abs(w - lastFittingWidth) > 0.5 {
            lastFittingWidth = w
            publishMeasuredHeight()
            invalidateIntrinsicContentSize()
        }
        let natural = unconstrainedContentHeight()
        let needsScroll = natural > maxComposerHeight + 0.5
        if isScrollEnabled != needsScroll {
            isScrollEnabled = needsScroll
            showsVerticalScrollIndicator = needsScroll
        }
    }
}

private struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    var focusToken: Int
    var maxHeight: CGFloat
    var fontSize: CGFloat
    var centerVerticallyWhenSingleLine: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, measuredHeight: $measuredHeight)
    }

    func makeUIView(context: Context) -> ComposerSizingTextView {
        let tv = ComposerSizingTextView()
        tv.maxComposerHeight = maxHeight
        tv.centerVerticallyWhenSingleLine = centerVerticallyWhenSingleLine
        tv.delegate = context.coordinator
        tv.adjustsFontForContentSizeCategory = false
        tv.font = UIFont.systemFont(ofSize: fontSize, weight: .regular)
        tv.textColor = UIColor(red: 0.07, green: 0.10, blue: 0.20, alpha: 1)
        tv.backgroundColor = .clear
        tv.textContainer.lineFragmentPadding = 0
        tv.isScrollEnabled = false
        tv.showsVerticalScrollIndicator = false
        tv.alwaysBounceVertical = false
        // Nunca cerrar teclado al scrollear dentro del campo.
        tv.keyboardDismissMode = .none
        tv.autocorrectionType = .yes
        tv.smartInsertDeleteType = .yes
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.defaultHigh, for: .vertical)
        tv.textContainer.widthTracksTextView = false
        tv.onMeasuredHeightChange = { height in
            DispatchQueue.main.async {
                context.coordinator.measuredHeight.wrappedValue = height
            }
        }
        applyTextStyle(to: tv, string: text)
        tv.refreshVerticalInsets(forText: text)
        tv.publishMeasuredHeight()
        context.coordinator.lastFocusToken = focusToken
        return tv
    }

    func updateUIView(_ tv: ComposerSizingTextView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.measuredHeight = $measuredHeight
        tv.maxComposerHeight = maxHeight
        tv.centerVerticallyWhenSingleLine = centerVerticallyWhenSingleLine
        tv.keyboardDismissMode = .none
        tv.onMeasuredHeightChange = { height in
            DispatchQueue.main.async {
                if abs(context.coordinator.measuredHeight.wrappedValue - height) > 0.5 {
                    context.coordinator.measuredHeight.wrappedValue = height
                }
            }
        }
        if tv.text != text {
            applyTextStyle(to: tv, string: text)
        } else {
            applyTypingAttributes(to: tv)
        }
        tv.refreshVerticalInsets(forText: text)
        tv.publishMeasuredHeight()
        tv.invalidateIntrinsicContentSize()

        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                if !tv.isFirstResponder {
                    tv.becomeFirstResponder()
                }
            }
        }
    }

    private var textColor: UIColor {
        UIColor(red: 0.07, green: 0.10, blue: 0.20, alpha: 1)
    }

    private var paragraphStyle: NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 0
        paragraph.lineHeightMultiple = 1.0
        paragraph.paragraphSpacing = 0
        paragraph.paragraphSpacingBefore = 0
        return paragraph
    }

    private func attributes() -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
        ]
    }

    private func applyTypingAttributes(to tv: UITextView) {
        tv.typingAttributes = attributes()
        tv.font = UIFont.systemFont(ofSize: fontSize, weight: .regular)
        tv.textColor = textColor
    }

    private func applyTextStyle(to tv: UITextView, string: String) {
        applyTypingAttributes(to: tv)
        let selected = tv.selectedRange
        tv.attributedText = NSAttributedString(string: string, attributes: attributes())
        let len = (string as NSString).length
        if selected.location <= len {
            tv.selectedRange = NSRange(location: min(selected.location, len), length: 0)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var measuredHeight: Binding<CGFloat>
        var lastFocusToken = 0

        init(text: Binding<String>, measuredHeight: Binding<CGFloat>) {
            self.text = text
            self.measuredHeight = measuredHeight
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text ?? ""
            guard let v = textView as? ComposerSizingTextView else { return }
            v.refreshVerticalInsets(forText: textView.text ?? "")
            v.publishMeasuredHeight(scrollToCaret: true)
            v.invalidateIntrinsicContentSize()
        }
    }
}

// MARK: - Fondo conversación (Telegram: mint → sky + patrón)

private struct ConversationBackdrop: View {
    var body: some View {
        GrooChatWallpaper()
            .ignoresSafeArea()
    }
}

#Preview {
    NavigationStack {
        ChatConversationView(
            thread: ChatThread(
                id: UUID(),
                title: "@amosrz",
                preview: "Hola",
                time: "15:41",
                unread: nil,
                avatarInitial: "A",
                avatarIcon: nil,
                avatarR: 0.69,
                avatarG: 0.32,
                avatarB: 0.87,
                avatarCarURL: nil,
                socialSource: .instagram,
                isVerified: false,
                isPinned: false,
                kind: .lead,
                peerUserId: nil,
                readReceipt: .none,
                showOpenButton: false,
                lastActivityAt: Date()
            )
        )
            .environmentObject(ChatInboxStore())
            .environmentObject(DashboardCommunityViewModel())
            .environmentObject(AuthViewModel())
            .environmentObject(UserModerationStore())
            .environmentObject(ChatVoicePlaybackCoordinator.shared)
    }
}
