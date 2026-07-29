import AVFoundation
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
    @State private var reportTarget: ModerationTarget?
    @State private var showBlockConfirm = false
    @State private var moderationAlertMessage: String?
    @State private var showModerationAlert = false
    @State private var showObjectionableContentAlert = false
    @State private var softphoneTarget: SoftphoneTarget?
    @State private var imageLightboxItem: GrooChatImageLightboxItem?

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

    private var stackedConversationMessages: [ChatMessage] {
        if usesTeamGroupServer { return teamGroupUIMessages + liveMessages }
        if usesTeamDirectServer { return teamDirectUIMessages + liveMessages }
        if usesCrmServer { return mergedCrmConversationMessages }
        if thread.kind == .lead { return liveMessages }
        return mockMsgs + liveMessages
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

    /// ¿La IA está encendida para este chat? (por defecto sí).
    private var crmAiActive: Bool {
        chatInbox.crmAiActiveByThread[thread.id] ?? true
    }

    private func toggleCrmAi(to active: Bool) {
        guard let convId = chatInbox.crmConversationIdByThread[thread.id],
              let token = auth.session?.accessToken else { return }
        chatInbox.setCrmAiActiveLocal(threadId: thread.id, active: active)
        Task {
            do {
                try await CrmChatService.setAiActive(token: token, conversationId: convId, active: active)
            } catch {
                // Si falla, revertimos el estado local.
                await MainActor.run { chatInbox.setCrmAiActiveLocal(threadId: thread.id, active: !active) }
            }
        }
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
        let msgs = teamDirectUIMessages + liveMessages
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
            if chatInbox.canCallLead(thread),
               let phone = chatInbox.contactPhoneDisplay(for: thread) {
                return phone
            }
            return "últ. vez recientemente"
        }
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

    /// Margen desde el borde seguro hasta el contenido del chat, alineado visualmente con barra de navegación (atrás / avatar ~40pt).
    private let navBarContentInset: CGFloat = 20
    /// Espacio mínimo entre burbuja y el lado opuesto dentro del ancho útil.
    private let bubbleEdgeMargin: CGFloat = 12

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
                                    }
                                }
                            } else {
                                ForEach(stackedConversationMessages) { msg in
                                    messageBubble(msg, maxBubbleWidth: maxBubble)
                                        .frame(maxWidth: innerW)
                                        .id(msg.id)
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
                    .scrollDismissesKeyboard(.interactively)
                    .simultaneousGesture(
                        TapGesture().onEnded { _ in
                            dismissComposerKeyboard()
                        }
                    )
                    .onChange(of: stackedConversationMessages.count) { _, _ in
                        scrollChatToBottom(proxy: proxy)
                    }
                    .onChange(of: teamDirectTimelineItems.count) { _, _ in
                        if usesTeamDirectServer { scrollChatToBottom(proxy: proxy) }
                    }
                    .onAppear {
                        scrollChatToBottom(proxy: proxy, animated: false)
                    }
                }

                whatsAppConversationHeader
            }
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
            inputBarChrome(
                leadingPad: inputBarHorizontalPadding.leading,
                trailingPad: inputBarHorizontalPadding.trailing
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .onChange(of: selectedPhoto) { _, newItem in
            Task { await handleSelectedPhoto(newItem) }
        }
        .onAppear {
            if thread.kind == .lead {
                chatInbox.activeLeadThreadId = thread.id
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
            if thread.kind == .lead {
                chatInbox.activeLeadThreadId = nil
            }
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
            }
        }
        .alert("Nota de voz", isPresented: Binding(
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
        .fullScreenCover(item: $softphoneTarget) { target in
            SoftphoneCallView(
                target: target,
                accessToken: auth.session?.accessToken
            ) {
                softphoneTarget = nil
            }
        }
        .fullScreenCover(item: $imageLightboxItem) { item in
            GrooChatImageLightbox(item: item)
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
            if isRecordingTeamVoice {
                Text("Toca el micrófono otra vez para enviar el audio")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.45))
            }
            messageInputBar
        }
        .padding(.horizontal, 10)
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

            VStack(spacing: 1) {
                Text(thread.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(chatToolbarNameColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(conversationStatusLine)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(chatToolbarStatusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background { GrooChatTheme.glassPillBackground() }
            .layoutPriority(1)

            Spacer(minLength: 4)

            conversationHeaderAvatar
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.95), lineWidth: 1.5)
                }
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)

            if usesCrmServer {
                whatsAppCrmActionsPill
            } else if usesTeamDirectServer || usesTeamGroupServer {
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

    private var whatsAppCrmActionsPill: some View {
        HStack(spacing: 14) {
            Button {
                toggleCrmAi(to: !crmAiActive)
            } label: {
                Image(systemName: crmAiActive ? "cpu.fill" : "cpu")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        crmAiActive
                            ? GrooChatTheme.telegramBlue
                            : Color.black.opacity(0.75)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(crmAiActive ? "Desactivar IA" : "Activar IA")

            if chatInbox.canCallLead(thread),
               let phone = chatInbox.contactPhone(for: thread) {
                Button {
                    softphoneTarget = SoftphoneTarget(number: phone, name: thread.title)
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GrooChatTheme.telegramBlue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Llamar")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background { GrooChatTheme.glassPillBackground() }
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
            directory: communityVM.directory,
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
                } else if let text = msg.text {
                    if msg.isOutgoing {
                        outgoingTextBubble(text: text, time: msg.time, receipt: msg.receipt ?? .sent, maxBubbleWidth: maxBubbleWidth)
                    } else {
                        incomingTextBubble(text: text, time: msg.time, maxBubbleWidth: maxBubbleWidth)
                    }
                }
            }
            .frame(maxWidth: maxBubbleWidth, alignment: msg.isOutgoing ? .trailing : .leading)

            if !msg.isOutgoing {
                Spacer(minLength: bubbleEdgeMargin)
            }
        }
        .frame(maxWidth: .infinity, alignment: msg.isOutgoing ? .trailing : .leading)
        .contextMenu {
            if let senderId = msg.senderUserId, !msg.isOutgoing, auth.session?.user.id != senderId {
                Button {
                    reportTarget = moderationTarget(
                        userId: senderId,
                        contentType: usesTeamGroupServer ? .teamGroupMessage : .teamDirectMessage,
                        contentId: msg.id,
                        contentPreview: msg.text
                    )
                } label: {
                    Label("Denunciar contenido", systemImage: "exclamationmark.bubble")
                }
                Button(role: .destructive) {
                    reportTarget = moderationTarget(
                        userId: senderId,
                        contentType: usesTeamGroupServer ? .teamGroupMessage : .teamDirectMessage,
                        contentId: msg.id,
                        contentPreview: msg.text
                    )
                    showBlockConfirm = true
                } label: {
                    Label("Bloquear usuario", systemImage: "hand.raised.fill")
                }
            }
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

    private func outgoingTextBubble(text: String, time: String, receipt: OutgoingReceipt, maxBubbleWidth: CGFloat) -> some View {
        let shape = GrooMessageBubbleShape(isOutgoing: true, isLastInGroup: true)

        return Group {
            if chatTextFitsSingleLineWithMeta(text: text, time: time, maxBubbleWidth: maxBubbleWidth, outgoing: true, receipt: receipt) {
                HStack(alignment: .bottom, spacing: 6) {
                    Text(text)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(outgoingBubbleTextColor)
                        .lineLimit(1)
                    outgoingMetaRow(time: time, receipt: receipt)
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
                    .padding(.trailing, 72)
                    .padding(.bottom, 2)
                    .overlay(alignment: .bottomTrailing) {
                        outgoingMetaRow(time: time, receipt: receipt)
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
        receipt: OutgoingReceipt?
    ) -> Bool {
        guard !text.contains(where: \.isNewline) else { return false }
        let inner = maxBubbleWidth - 2 * bubblePadH
        let bodyFont = UIFont.systemFont(ofSize: 16, weight: .regular)
        let metaFont = UIFont.systemFont(ofSize: 11, weight: .medium)
        let textW = (text as NSString).size(withAttributes: [.font: bodyFont]).width
        let timeW = (time as NSString).size(withAttributes: [.font: metaFont]).width
        if outgoing, let receipt {
            let checkW: CGFloat = receipt == .sent ? 13 : 17
            let row = textW + 6 + timeW + 4 + checkW
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

    private func outgoingMetaRow(time: String, receipt: OutgoingReceipt) -> some View {
        HStack(spacing: 3) {
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

    private let composerFontSize: CGFloat = 16
    private let composerVerticalPadding: CGFloat = 10
    private let composerTextTopInset: CGFloat = 2
    private let composerTextBottomInset: CGFloat = 2

    /// ~mitad de pantalla: el texto hace scroll dentro si supera este alto.
    private var composerTextScrollMaxHeight: CGFloat {
        let h = UIScreen.main.bounds.height
        return max(120, h * 0.42)
    }

    private var composerIsMultiline: Bool {
        draft.contains(where: \.isNewline) || draft.count > 36
    }

    private var messageInputBar: some View {
        HStack(alignment: draftIsEmpty ? .center : .bottom, spacing: 8) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Image(systemName: "paperclip")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.65))
                    .frame(width: 40, height: 40)
                    .background { GrooChatTheme.glassCircleBackground() }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isChatDictating || isRecordingTeamVoice || isSendingVoiceNote || isSendingImage)

            HStack(alignment: draftIsEmpty ? .center : .bottom, spacing: 8) {
                ZStack(alignment: draftIsEmpty ? .leading : .topLeading) {
                    ComposerTextView(
                        text: $draft,
                        maxHeight: composerTextScrollMaxHeight,
                        fontSize: composerFontSize,
                        textTopInset: composerTextTopInset,
                        textBottomInset: composerTextBottomInset
                    )
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity((isChatDictating || isRecordingTeamVoice || isSendingVoiceNote) ? 0.2 : 1)

                    if isSendingVoiceNote {
                        Text("Enviando audio…")
                            .font(.system(size: composerFontSize))
                            .foregroundStyle(Color.black.opacity(0.4))
                            .padding(.top, composerTextTopInset)
                            .allowsHitTesting(false)
                    } else if isSendingImage {
                        Text("Enviando imagen…")
                            .font(.system(size: composerFontSize))
                            .foregroundStyle(Color.black.opacity(0.4))
                            .padding(.top, composerTextTopInset)
                            .allowsHitTesting(false)
                    } else if isRecordingTeamVoice {
                        Text("Grabando… Toca el micrófono para enviar")
                            .font(.system(size: composerFontSize))
                            .foregroundStyle(Color.black.opacity(0.4))
                            .padding(.top, composerTextTopInset)
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
                        .padding(.top, composerTextTopInset)
                        .allowsHitTesting(false)
                    } else if draftIsEmpty && !isRecordingTeamVoice {
                        Text("Mensaje")
                            .font(.system(size: composerFontSize))
                            .foregroundStyle(Color.black.opacity(0.35))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 22)

                if draftIsEmpty && !isRecordingTeamVoice && !isSendingVoiceNote && !isChatDictating {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.35))
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                } else if !draftIsEmpty {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.35))
                        .frame(width: 28, height: 28)
                        .padding(.bottom, 1)
                        .accessibilityHidden(true)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .padding(.vertical, draftIsEmpty ? 8 : (composerIsMultiline ? 12 : composerVerticalPadding))
            .frame(maxWidth: .infinity, minHeight: 40, alignment: draftIsEmpty ? .center : .bottom)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.white.opacity(0.88)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.98), lineWidth: 1))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            }

            if !draftIsEmpty {
                Button { sendMessage() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(whatsAppSendGreen, in: Circle())
                        .shadow(color: GrooChatTheme.telegramBlue.opacity(0.3), radius: 8, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(isChatDictating || isRecordingTeamVoice || isSendingVoiceNote)
                .accessibilityLabel("Enviar mensaje")
            } else {
                Group {
                    if usesTeamDirectServer || usesCrmServer {
                        VoiceNoteMicTapControl(
                            isRecording: isRecordingTeamVoice,
                            isBusy: isSendingVoiceNote
                        ) {
                            toggleVoiceNoteRecording()
                        }
                    } else {
                        Button {
                            toggleChatDictation()
                        } label: {
                            Image(systemName: isChatDictating ? "stop.fill" : "mic.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(isChatDictating ? Color.red.opacity(0.9) : Color.black.opacity(0.65))
                                .frame(width: 40, height: 40)
                                .background { GrooChatTheme.glassCircleBackground() }
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isChatDictating ? "Detener dictado" : "Dictar mensaje")
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: composerIsMultiline)
        .animation(.easeInOut(duration: 0.2), value: draftIsEmpty)
        .animation(.easeInOut(duration: 0.2), value: draft.count)
        .animation(.easeInOut(duration: 0.2), value: isChatDictating)
        .animation(.easeInOut(duration: 0.2), value: isRecordingTeamVoice)
        .animation(.easeInOut(duration: 0.2), value: isSendingVoiceNote)
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
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
        teamVoiceRecorder?.stop()
        teamVoiceRecorder = nil
        if let url = teamVoiceURL {
            try? FileManager.default.removeItem(at: url)
        }
        teamVoiceURL = nil
        isRecordingTeamVoice = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
        guard usesTeamDirectServer || usesCrmServer else { return }
        guard auth.session != nil else { return }
        if usesTeamDirectServer, thread.peerUserId == nil { return }
        if usesCrmServer, chatInbox.crmConversationIdByThread[thread.id] == nil { return }
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

        guard let url = teamVoiceURL else {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        teamVoiceURL = nil

        let nbytes = await awaitVoiceNoteFileReady(at: url) ?? 0
        guard recordedSeconds >= 0.35, nbytes > 400 else {
            cleanupVoiceNoteFile(at: url)
            if nbytes == 0 {
                teamVoiceError = "No se capturó audio. Revisa permisos del micrófono o prueba en un iPhone físico (el simulador a veces falla)."
            } else {
                teamVoiceError = "La grabación es demasiado corta. Graba un poco más antes de enviar."
            }
            return
        }

        isSendingVoiceNote = true
        defer {
            isSendingVoiceNote = false
            cleanupVoiceNoteFile(at: url)
        }

        if usesCrmServer,
           let convId = chatInbox.crmConversationIdByThread[thread.id],
           let token = auth.session?.accessToken {
            let now = Self.currentTimeString()
            withAnimation {
                liveMessages.append(
                    ChatMessage(remoteAudioURL: url, isOutgoing: true, time: now, receipt: .sent)
                )
            }
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
        withAnimation {
            liveMessages.append(
                ChatMessage(
                    image: image,
                    caption: caption.isEmpty ? nil : caption,
                    isOutgoing: true,
                    time: now,
                    receipt: .sent
                )
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
        withAnimation {
            liveMessages.append(optimistic)
        }
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
        withAnimation {
            liveMessages.append(ChatMessage(text: trimmed, isOutgoing: true, time: now, receipt: .sent))
        }
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
                }
            }
        }
    }

    private func sendMessage() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if ContentModerationFilter.containsObjectionableContent(text) {
            showObjectionableContentAlert = true
            return
        }
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
        withAnimation {
            liveMessages.append(ChatMessage(text: text, isOutgoing: true, time: now, receipt: .sent))
        }
        draft = ""
    }

    // MARK: - Conversación real del CRM (WhatsApp/Instagram)

    /// Carga los mensajes reales y los refresca cada 6 s mientras el chat está abierto.
    private func runCrmSessionIfNeeded() async {
        guard thread.kind == .lead else { return }
        while !Task.isCancelled {
            await refreshCrmMessages(clearLocal: false)
            try? await Task.sleep(nanoseconds: 6_000_000_000)
        }
    }

    @MainActor
    private func refreshCrmMessages(clearLocal: Bool) async {
        guard let convId = chatInbox.crmConversationIdByThread[thread.id],
              let token = auth.session?.accessToken
        else { return }
        guard let rows = try? await CrmChatService.messages(token: token, conversationId: convId, limit: 100)
        else { return }
        crmRows = rows
        if clearLocal {
            liveMessages.removeAll()
        } else {
            let serverOutgoingTexts = Set(
                rows
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
                    let hasServerImage = rows.contains { row in
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
        if let preview = CrmChatService.latestInboxPreview(from: rows) {
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

    var fileExtension: String {
        switch self {
        case .supabase: return "m4a"
        case .remote(let url, _):
            let ext = url.pathExtension.lowercased()
            if !ext.isEmpty { return ext }
            if url.scheme?.lowercased() == "data" {
                let raw = url.absoluteString.lowercased()
                if raw.contains("ogg") { return "ogg" }
                if raw.contains("mpeg") || raw.contains("mp3") { return "mp3" }
            }
            return "ogg"
        }
    }
}

private struct VoiceNoteBubbleView: View {
    let source: VoiceAudioSource
    let isOutgoing: Bool
    let time: String
    let receipt: OutgoingReceipt?
    let maxBubbleWidth: CGFloat

    @State private var isPlaying = false
    @State private var isPlayLoading = false
    @State private var isPrefetching = false
    @State private var loadFailed = false
    @State private var cachedAudioData: Data?
    @State private var waveformBars: [CGFloat] = []
    @State private var audioDuration: TimeInterval = 0
    @State private var player: AVAudioPlayer?
    @State private var streamPlayer: AVPlayer?
    @State private var playbackToken = UUID()
    @State private var playFileURL: URL?
    @State private var streamEndObserver: NSObjectProtocol?

    private let incomingBubbleFill = Color.white.opacity(0.92)
    private let incomingMeta = Color.black.opacity(0.38)
    private let outgoingMeta = Color.black.opacity(0.38)
    private let bubblePadH: CGFloat = 12
    private let bubblePadV: CGFloat = 10
    private let bubbleCorner: CGFloat = 18
    private let waveformBarCount = 42
    private let waveformStripHeight: CGFloat = 28
    private let playButtonSize: CGFloat = 40

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: bubbleCorner, style: .continuous)
        Button {
            togglePlayback()
        } label: {
            HStack(alignment: .center, spacing: 10) {
                playCircleButton

                VStack(alignment: .leading, spacing: 6) {
                    playbackWaveform

                    HStack(alignment: .center, spacing: 8) {
                        durationLabel
                        Spacer(minLength: 4)
                        bubbleMetaRow
                    }

                    if loadFailed && waveformBars.isEmpty {
                        Text("No se pudo cargar el audio")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.orange.opacity(0.95))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .disabled(isPlayLoading)
        .padding(.horizontal, bubblePadH)
        .padding(.vertical, bubblePadV)
        .frame(maxWidth: maxBubbleWidth, alignment: isOutgoing ? .trailing : .leading)
        .background {
            if isOutgoing {
                shape.fill(GrooChatTheme.outgoingBubble)
            } else {
                shape.fill(incomingBubbleFill)
            }
        }
        .task(id: source.taskID) {
            await prefetchWaveform()
        }
        .onDisappear {
            stopPlaybackCleanup()
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
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: isPlaying ? 15 : 14, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: isPlaying ? 0 : 1.5)
            }
        }
        .opacity(isPlayLoading ? 0.85 : 1)
    }

    @ViewBuilder
    private var playbackWaveform: some View {
        Group {
            if isPlaying {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { _ in
                    voiceWaveformStrip(progress: playbackProgress)
                }
            } else {
                voiceWaveformStrip(progress: 0)
            }
        }
        .frame(height: waveformStripHeight)
    }

    private func voiceWaveformStrip(progress: CGFloat) -> some View {
        VoiceMessageWaveformStrip(
            bars: waveformBars,
            progress: progress,
            isLoading: isPrefetching && waveformBars.isEmpty,
            accentColor: GrooChatTheme.telegramBlue,
            stripHeight: waveformStripHeight,
            onSeek: audioDuration > 0 ? { fraction in
                seekToProgress(fraction)
            } : nil
        )
    }

    @MainActor
    private func seekToProgress(_ fraction: CGFloat) {
        guard audioDuration > 0 else { return }
        let target = min(audioDuration, max(0, Double(fraction) * audioDuration))

        if player == nil, streamPlayer == nil, let data = cachedAudioData {
            do {
                try playData(data, fileExtension: source.fileExtension)
            } catch {
                loadFailed = true
                return
            }
        }

        if let player {
            player.currentTime = target
            if !isPlaying {
                player.play()
                isPlaying = true
            }
            return
        }
        if let streamPlayer {
            let time = CMTime(seconds: target, preferredTimescale: 600)
            streamPlayer.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            if !isPlaying {
                streamPlayer.play()
                isPlaying = true
            }
        }
    }

    private var currentPlaybackTime: TimeInterval {
        if let player {
            return player.currentTime
        }
        if let streamPlayer {
            let t = streamPlayer.currentTime().seconds
            return t.isFinite ? max(0, t) : 0
        }
        return 0
    }

    private var playbackProgress: CGFloat {
        guard audioDuration > 0 else { return 0 }
        return min(1, CGFloat(currentPlaybackTime / audioDuration))
    }

    @ViewBuilder
    private var durationLabel: some View {
        HStack(spacing: 5) {
            if isPlaying {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { _ in
                    Text(VoiceMessageWaveformExtractor.formatDuration(currentPlaybackTime))
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(incomingMeta)
                }
            } else {
                Text(VoiceMessageWaveformExtractor.formatDuration(audioDuration))
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(incomingMeta)
            }

            if isPlaying {
                Circle()
                    .fill(GrooChatTheme.telegramBlue)
                    .frame(width: 6, height: 6)
            }
        }
    }

    @ViewBuilder
    private var bubbleMetaRow: some View {
        HStack(spacing: 3) {
            Text(time)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(isOutgoing ? outgoingMeta : incomingMeta)
            if isOutgoing, let receipt {
                voiceReceiptMarks(receipt)
            }
        }
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
            let barN = waveformBarCount
            let bars = await Task.detached(priority: .userInitiated) {
                VoiceMessageWaveformExtractor.waveformBars(
                    fromAudioData: data,
                    fileExtension: ext,
                    barCount: barN
                )
            }.value
            let dur = VoiceMessageWaveformExtractor.durationSeconds(ofAudioData: data, fileExtension: ext) ?? 0
            await MainActor.run {
                cachedAudioData = data
                waveformBars = bars
                audioDuration = dur > 0 ? dur : 0
                isPrefetching = false
            }
        } catch {
            await MainActor.run {
                isPrefetching = false
                loadFailed = true
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
            return try await CrmAudioLoader.download(url: url, accessToken: token)
        }
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlaybackCleanup()
            return
        }
        loadFailed = false
        if let data = cachedAudioData {
            isPlayLoading = true
            Task { @MainActor in
                defer { isPlayLoading = false }
                do {
                    try playData(data, fileExtension: source.fileExtension)
                } catch {
                    loadFailed = true
                }
            }
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
                    audioDuration = VoiceMessageWaveformExtractor.durationSeconds(
                        ofAudioData: data,
                        fileExtension: src.fileExtension
                    ) ?? 0
                    isPlayLoading = false
                    do {
                        try playData(data, fileExtension: src.fileExtension)
                    } catch {
                        loadFailed = true
                    }
                }
            } catch {
                await MainActor.run {
                    isPlayLoading = false
                    loadFailed = true
                }
            }
        }
    }

    @MainActor
    private func stopPlaybackCleanup() {
        player?.stop()
        player = nil
        streamPlayer?.pause()
        streamPlayer = nil
        if let obs = streamEndObserver {
            NotificationCenter.default.removeObserver(obs)
            streamEndObserver = nil
        }
        isPlaying = false
        playbackToken = UUID()
        if let url = playFileURL {
            try? FileManager.default.removeItem(at: url)
            playFileURL = nil
        }
    }

    @MainActor
    private func playData(_ data: Data, fileExtension: String) throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try AVAudioSession.sharedInstance().setActive(true)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("voice-play-\(UUID().uuidString).\(fileExtension)")
        try data.write(to: temp)
        playFileURL = temp

        if fileExtension == "m4a" || fileExtension == "mp4" || fileExtension == "mp3" || fileExtension == "aac" || fileExtension == "wav" {
            do {
                let p = try AVAudioPlayer(contentsOf: temp)
                p.prepareToPlay()
                let duration = max(p.duration, 0.35)
                if audioDuration < 0.5 { audioDuration = duration }
                guard p.play() else { throw NSError(domain: "Drflow", code: 3) }
                player = p
                isPlaying = true
                let token = UUID()
                playbackToken = token
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64((duration + 0.15) * 1_000_000_000))
                    guard playbackToken == token else { return }
                    stopPlaybackCleanup()
                }
                return
            } catch {}
        }

        let item = AVPlayerItem(url: temp)
        let av = AVPlayer(playerItem: item)
        streamPlayer = av
        isPlaying = true
        let token = UUID()
        playbackToken = token
        streamEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            Task { @MainActor in
                guard playbackToken == token else { return }
                stopPlaybackCleanup()
            }
        }
        av.play()
        Task { @MainActor in
            let asset = AVURLAsset(url: temp)
            if #available(iOS 16.0, *) {
                if let loaded = try? await asset.load(.duration) {
                    let seconds = CMTimeGetSeconds(loaded)
                    if seconds.isFinite, seconds > 0, audioDuration < 0.5 {
                        audioDuration = seconds
                    }
                    return
                }
            }
            let seconds = CMTimeGetSeconds(asset.duration)
            if seconds.isFinite, seconds > 0, audioDuration < 0.5 {
                audioDuration = seconds
            }
        }
    }
}

// MARK: - Campo multilínea con scroll (UITextView)

/// Altura intrínseca = contenido hasta `maxComposerHeight`; solo entonces activa scroll (caja “grandote”).
private final class ComposerSizingTextView: UITextView {
    var maxComposerHeight: CGFloat = 200

    private var widthForFitting: CGFloat {
        if bounds.width > 2 { return bounds.width }
        return max(120, UIScreen.main.bounds.width - 100)
    }

    override var intrinsicContentSize: CGSize {
        let minLine = (font?.lineHeight ?? 22) + textContainerInset.top + textContainerInset.bottom
        let str = text ?? ""
        if str.isEmpty {
            return CGSize(width: UIView.noIntrinsicMetric, height: minLine)
        }
        layoutManager.ensureLayout(for: textContainer)
        let tw = widthForFitting - textContainerInset.left - textContainerInset.right
        let used = sizeThatFits(CGSize(width: max(tw, 40), height: .greatestFiniteMagnitude))
        let h = min(max(used.height, minLine), maxComposerHeight)
        return CGSize(width: UIView.noIntrinsicMetric, height: h)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let overflow = contentSize.height > bounds.height + 2
        if isScrollEnabled != overflow {
            isScrollEnabled = overflow
        }
        invalidateIntrinsicContentSize()
    }
}

private struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    var maxHeight: CGFloat
    var fontSize: CGFloat
    var textTopInset: CGFloat
    var textBottomInset: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> ComposerSizingTextView {
        let tv = ComposerSizingTextView()
        tv.maxComposerHeight = maxHeight
        tv.delegate = context.coordinator
        tv.adjustsFontForContentSizeCategory = true
        let base = UIFont.systemFont(ofSize: fontSize, weight: .regular)
        tv.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
        tv.textColor = UIColor(red: 0.07, green: 0.10, blue: 0.20, alpha: 1)
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: textTopInset, left: 0, bottom: textBottomInset, right: 0)
        tv.textContainer.lineFragmentPadding = 0
        tv.isScrollEnabled = false
        tv.keyboardDismissMode = .interactive
        tv.autocorrectionType = .yes
        tv.smartInsertDeleteType = .yes
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.textContainer.widthTracksTextView = true
        tv.text = text
        return tv
    }

    func updateUIView(_ tv: ComposerSizingTextView, context: Context) {
        tv.maxComposerHeight = maxHeight
        tv.textContainerInset = UIEdgeInsets(top: textTopInset, left: 0, bottom: textBottomInset, right: 0)
        let base = UIFont.systemFont(ofSize: fontSize, weight: .regular)
        tv.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
        tv.textColor = UIColor(red: 0.07, green: 0.10, blue: 0.20, alpha: 1)
        if tv.text != text {
            let range = tv.selectedRange
            tv.text = text
            let len = (text as NSString).length
            if range.location <= len {
                tv.selectedRange = range
            }
        }
        tv.invalidateIntrinsicContentSize()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
            textView.invalidateIntrinsicContentSize()
            if let v = textView as? ComposerSizingTextView {
                DispatchQueue.main.async {
                    v.invalidateIntrinsicContentSize()
                }
            }
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
    }
}
