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
        isOutgoing: Bool,
        time: String,
        receipt: OutgoingReceipt? = nil,
        sortKey: Date = Date(),
        voiceStoragePath: String? = nil,
        senderUserId: UUID? = nil
    ) {
        self.id = id
        self.text = nil
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
    @State private var teamVoiceRecorder: AVAudioRecorder?
    @State private var teamVoiceURL: URL?
    @State private var teamVoiceError: String?
    @State private var reportTarget: ModerationTarget?
    @State private var showBlockConfirm = false
    @State private var moderationAlertMessage: String?
    @State private var showModerationAlert = false
    @State private var showObjectionableContentAlert = false
    @State private var softphoneTarget: SoftphoneTarget?

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
        if usesCrmServer { return crmUIMessages + liveMessages }
        return mockMsgs + liveMessages
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
                let incoming = (row.senderType ?? "contact") == "contact"
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
        if CrmChatService.isAudioMessage(row) { return nil }
        let type = (row.mediaType ?? row.messageType ?? "").lowercased()
        let isImageType = type.contains("image") || type.hasPrefix("img")
        // a) URL pública directa
        if let urlStr = row.mediaUrl, let url = URL(string: urlStr) {
            let lower = urlStr.lowercased()
            let looksImage = isImageType
                || lower.contains(".jpg") || lower.contains(".jpeg")
                || lower.contains(".png") || lower.contains(".webp") || lower.contains(".heic")
            if looksImage { return url }
        }
        // b) base64 incrustado (data URL) cuando es imagen
        if isImageType, let b64 = row.mediaContent, !b64.isEmpty {
            let clean = b64.contains(",") ? String(b64.split(separator: ",").last ?? "") : b64
            let mime = type.contains("/") ? type : "image/jpeg"
            if let url = URL(string: "data:\(mime);base64,\(clean)") { return url }
        }
        return nil
    }

    private static func looksLikePlaceholder(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t == "📷 Imagen" || t == "📎 Archivo adjunto" || t.count <= 1
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

    /// Cabecera conversación estilo WhatsApp.
    private let chatToolbarNameColor = Color.white
    private let chatToolbarStatusColor = Color(red: 0.62, green: 0.66, blue: 0.72)
    private let whatsAppFieldFill = Color(red: 0.11, green: 0.11, blue: 0.11)
    private let whatsAppSendGreen = Color(red: 0.0, green: 0.72, blue: 0.45)
    private let whatsAppComposerInset: CGFloat = 8
    /// Entrantes: fondo pizarra azulada; texto blanco; hora en gris claro visible.
    private let incomingBubbleTextColor = Color.white
    private let incomingBubbleMetaColor = Color(red: 0.72, green: 0.76, blue: 0.82)

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

            ZStack {
                ConversationBackdrop()

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 8) {
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
        .safeAreaInset(edge: .top, spacing: 0) {
            whatsAppConversationHeader
        }
        .onChange(of: selectedPhoto) { _, newItem in
            Task {
                guard let newItem else { return }
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    let now = Self.currentTimeString()
                    withAnimation {
                        liveMessages.append(ChatMessage(image: img, isOutgoing: true, time: now, receipt: .sent))
                    }
                }
                selectedPhoto = nil
            }
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
            Text("Dejarás de ver los mensajes de esta persona y se enviará un informe al equipo de Groo.")
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

    /// Barra inferior estilo WhatsApp (fondo negro, márgenes fijos).
    private func inputBarChrome(leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        VStack(spacing: 4) {
            if isRecordingTeamVoice {
                Text("Toca el micrófono otra vez para enviar el audio")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            messageInputBar
        }
        .padding(.horizontal, whatsAppComposerInset)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Cabecera WhatsApp

    private var whatsAppConversationHeader: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                    if let unread = thread.unread, unread > 0 {
                        Text("\(min(unread, 99))")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .foregroundStyle(.white.opacity(0.95))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)

            conversationHeaderAvatar

            VStack(alignment: .leading, spacing: 1) {
                Text(thread.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(chatToolbarNameColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(conversationStatusLine)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(chatToolbarStatusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            if usesCrmServer {
                whatsAppCrmActionsPill
            } else if usesTeamDirectServer || usesTeamGroupServer {
                teamConversationActionsMenu
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    private var whatsAppCrmActionsPill: some View {
        HStack(spacing: 18) {
            Button {
                toggleCrmAi(to: !crmAiActive)
            } label: {
                Image(systemName: crmAiActive ? "cpu.fill" : "cpu")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(
                        crmAiActive
                            ? Color(red: 0.15, green: 0.78, blue: 0.45)
                            : .white.opacity(0.92)
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
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Color(red: 0.15, green: 0.78, blue: 0.45))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Llamar")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background {
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75)
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
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 32, height: 32)
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
            diameter: 36
        )
    }

    // MARK: - Burbujas

    /// Salientes: azul intenso → cian (degradado horizontal).
    private let outgoingBubbleGradient = LinearGradient(
        colors: [
            Color(red: 0.0, green: 0.38, blue: 0.98),
            Color(red: 0.15, green: 0.78, blue: 0.95),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
    /// Entrantes: gris carbón con matiz fría (referencia burbuja oscura).
    private let incomingBubbleFill = Color(red: 0.12, green: 0.15, blue: 0.20)
    /// Hora y checks en salientes: blanco suavizado sobre el degradado.
    private let outgoingMetaTint = Color.white.opacity(0.78)
    private let outgoingMetaTintMuted = Color.white.opacity(0.52)
    private let bubblePadH: CGFloat = 11
    private let bubblePadV: CGFloat = 8
    private let bubbleCorner: CGFloat = 16

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
        let side = min(maxBubbleWidth, 240)
        VStack(alignment: msg.isOutgoing ? .trailing : .leading, spacing: 4) {
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
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: bubbleCorner, style: .continuous))

            if let caption = msg.text, !caption.trimmingCharacters(in: .whitespaces).isEmpty {
                if msg.isOutgoing {
                    outgoingTextBubble(text: caption, time: msg.time, receipt: msg.receipt ?? .sent, maxBubbleWidth: maxBubbleWidth)
                } else {
                    incomingTextBubble(text: caption, time: msg.time, maxBubbleWidth: maxBubbleWidth)
                }
            } else {
                Text(msg.time)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
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
        let contentCap = max(40, maxBubbleWidth - 2 * bubblePadH - 4)
        let shape = RoundedRectangle(cornerRadius: bubbleCorner, style: .continuous)

        return Group {
            if chatTextFitsSingleLineWithMeta(text: displayText, time: time, maxBubbleWidth: maxBubbleWidth, outgoing: false, receipt: nil) {
                HStack(alignment: .bottom, spacing: 6) {
                    Text(displayText)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(incomingBubbleTextColor)
                        .lineLimit(1)
                    Text(time)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(incomingBubbleMetaColor)
                }
                .padding(.horizontal, bubblePadH)
                .padding(.vertical, bubblePadV)
                .background { shape.fill(incomingBubbleFill) }
            } else {
                incomingTextMultiline(text: displayText, time: time, contentCap: contentCap, shape: shape)
            }
        }
        .frame(maxWidth: maxBubbleWidth, alignment: .leading)
    }

    private func incomingTextMultiline(text: String, time: String, contentCap: CGFloat, shape: RoundedRectangle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(incomingBubbleTextColor)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 0, maxWidth: contentCap, alignment: .leading)

            Text(time)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(incomingBubbleMetaColor)
                .frame(maxWidth: contentCap, alignment: .leading)
        }
        .padding(.horizontal, bubblePadH)
        .padding(.vertical, bubblePadV)
        .background { shape.fill(incomingBubbleFill) }
    }

    private func outgoingTextBubble(text: String, time: String, receipt: OutgoingReceipt, maxBubbleWidth: CGFloat) -> some View {
        let contentCap = max(40, maxBubbleWidth - 2 * bubblePadH - 4)
        let shape = RoundedRectangle(cornerRadius: bubbleCorner, style: .continuous)

        return Group {
            if chatTextFitsSingleLineWithMeta(text: text, time: time, maxBubbleWidth: maxBubbleWidth, outgoing: true, receipt: receipt) {
                HStack(alignment: .bottom, spacing: 6) {
                    Text(text)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    outgoingMetaRow(time: time, receipt: receipt)
                }
                .padding(.horizontal, bubblePadH)
                .padding(.vertical, bubblePadV)
                .background { shape.fill(outgoingBubbleGradient) }
            } else {
                outgoingTextMultiline(text: text, time: time, receipt: receipt, contentCap: contentCap, shape: shape)
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
        VStack(alignment: .trailing, spacing: 6) {
            Text(text)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 0, maxWidth: contentCap, alignment: .trailing)

            outgoingMetaRow(time: time, receipt: receipt)
                .frame(maxWidth: contentCap, alignment: .trailing)
        }
        .padding(.horizontal, bubblePadH)
        .padding(.vertical, bubblePadV)
        .background { shape.fill(outgoingBubbleGradient) }
    }

    private func outgoingMetaRow(time: String, receipt: OutgoingReceipt) -> some View {
        HStack(spacing: 4) {
            Text(time)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(outgoingMetaTint)
            outgoingReceiptMarks(receipt)
        }
    }

    @ViewBuilder
    private func outgoingReceiptMarks(_ receipt: OutgoingReceipt) -> some View {
        switch receipt {
        case .sent:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(outgoingMetaTint)
        case .delivered:
            outgoingDoubleCheckmarks(foreground: outgoingMetaTintMuted)
        case .read:
            outgoingDoubleCheckmarks(foreground: Color.white.opacity(0.92))
        }
    }

    private func outgoingDoubleCheckmarks(foreground: Color) -> some View {
        HStack(spacing: -5) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(foreground)
    }

    @ViewBuilder
    private func outgoingOrIncomingImageBubble(_ msg: ChatMessage, image: UIImage, maxBubbleWidth: CGFloat) -> some View {
        let maxW = min(220, maxBubbleWidth - 8)
        if msg.isOutgoing {
            VStack(alignment: .trailing, spacing: 4) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: maxW, maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                outgoingMetaRow(time: msg.time, receipt: msg.receipt ?? .sent)
            }
            .padding(6)
            .background {
                RoundedRectangle(cornerRadius: bubbleCorner, style: .continuous)
                    .fill(outgoingBubbleGradient)
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: maxBubbleWidth, alignment: .trailing)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: maxW, maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text(msg.time)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(incomingBubbleMetaColor)
            }
            .padding(6)
            .background {
                RoundedRectangle(cornerRadius: bubbleCorner, style: .continuous)
                    .fill(incomingBubbleFill)
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: maxBubbleWidth, alignment: .leading)
        }
    }

    // MARK: - Barra de entrada (estilo WhatsApp)

    private let composerFontSize: CGFloat = 16
    private let composerVerticalPadding: CGFloat = 6
    private let composerTextTopInset: CGFloat = 2
    private let composerTextBottomInset: CGFloat = 2

    /// ~mitad de pantalla: el texto hace scroll dentro si supera este alto.
    private var composerTextScrollMaxHeight: CGFloat {
        let h = UIScreen.main.bounds.height
        return max(120, h * 0.42)
    }

    private var messageInputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 28, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isChatDictating || isRecordingTeamVoice || isSendingVoiceNote)

            HStack(alignment: .bottom, spacing: 8) {
                ZStack(alignment: .leading) {
                    ComposerTextView(
                        text: $draft,
                        maxHeight: composerTextScrollMaxHeight,
                        fontSize: composerFontSize,
                        textTopInset: composerTextTopInset,
                        textBottomInset: composerTextBottomInset
                    )
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity((isChatDictating || isRecordingTeamVoice || isSendingVoiceNote) ? 0.2 : 1)

                    if isSendingVoiceNote {
                        Text("Enviando audio…")
                            .font(.system(size: composerFontSize))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.top, composerTextTopInset)
                            .allowsHitTesting(false)
                    } else if isRecordingTeamVoice {
                        Text("Grabando… Toca el micrófono para enviar")
                            .font(.system(size: composerFontSize))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.top, composerTextTopInset)
                            .allowsHitTesting(false)
                    } else if isChatDictating {
                        Group {
                            if chatDictationTranscriber.partialText.isEmpty {
                                Text("Escuchando…")
                                    .font(.system(size: composerFontSize))
                                    .foregroundStyle(.white.opacity(0.45))
                            } else {
                                Text(chatDictationTranscriber.partialText)
                                    .font(.system(size: composerFontSize))
                                    .foregroundStyle(.white.opacity(0.92))
                            }
                        }
                        .padding(.top, composerTextTopInset)
                        .allowsHitTesting(false)
                    } else if draftIsEmpty && !isRecordingTeamVoice {
                        Text("Mensaje")
                            .font(.system(size: composerFontSize))
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(.top, composerTextTopInset)
                            .allowsHitTesting(false)
                    }
                }

                if draftIsEmpty && !isRecordingTeamVoice && !isSendingVoiceNote && !isChatDictating {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 24, height: 28)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, composerVerticalPadding)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .center)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(whatsAppFieldFill)
            }

            if !draftIsEmpty {
                Button { sendMessage() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(whatsAppSendGreen, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isChatDictating || isRecordingTeamVoice || isSendingVoiceNote)
                .accessibilityLabel("Enviar mensaje")
            } else {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "camera")
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 28, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isChatDictating || isRecordingTeamVoice || isSendingVoiceNote)

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
                        Image(systemName: isChatDictating ? "stop.fill" : "mic")
                            .font(.system(size: 21, weight: .regular))
                            .foregroundStyle(isChatDictating ? Color.red.opacity(0.9) : .white.opacity(0.92))
                            .frame(width: 28, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isChatDictating ? "Detener dictado" : "Dictar mensaje")
                }
            }
        }
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
            let now = Self.currentTimeString()
            withAnimation {
                liveMessages.append(ChatMessage(text: text, isOutgoing: true, time: now, receipt: .sent))
            }
            Task {
                do {
                    try await CrmChatService.send(token: token, conversationId: convId, text: text)
                    await refreshCrmMessages(clearLocal: true)
                    await MainActor.run {
                        NotificationCenter.default.post(name: .messageDidRespond, object: nil)
                    }
                } catch {
                    // El backend rechazó el envío (p. ej. ventana de 24 h cerrada).
                    await MainActor.run {
                        liveMessages.removeAll { $0.text == text && $0.isOutgoing }
                        draft = text
                    }
                }
            }
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
        if clearLocal { liveMessages.removeAll() }
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
                ChatMessage(text: "Gracias, te escribo desde Groo.", isOutgoing: true, time: "10:18", receipt: .read)
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
                        .tint(.white.opacity(0.9))
                        .scaleEffect(0.75)
                } else {
                    Image(systemName: isRecording ? "stop.fill" : "mic")
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(isRecording ? Color.red.opacity(0.92) : .white.opacity(0.92))
                }
            }
            .frame(width: 28, height: 36)
            .contentShape(Rectangle())
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

    private let outgoingBubbleGradient = LinearGradient(
        colors: [
            Color(red: 0.0, green: 0.38, blue: 0.98),
            Color(red: 0.15, green: 0.78, blue: 0.95),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
    private let incomingBubbleFill = Color(red: 0.12, green: 0.15, blue: 0.20)
    private let incomingText = Color.white
    private let incomingMeta = Color(red: 0.72, green: 0.76, blue: 0.82)
    private let outgoingMeta = Color.white.opacity(0.78)
    private let bubblePadH: CGFloat = 11
    private let bubblePadV: CGFloat = 8
    private let bubbleCorner: CGFloat = 16
    private let waveformBarCount = 40
    private let waveformStripHeight: CGFloat = 36

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: bubbleCorner, style: .continuous)
        VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 8) {
            Button {
                togglePlayback()
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(isOutgoing ? Color.white : incomingText)
                        .opacity(isPlayLoading ? 0.55 : 1)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nota de voz")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isOutgoing ? Color.white.opacity(0.92) : incomingText.opacity(0.95))

                        waveformStrip

                        if loadFailed && waveformBars.isEmpty {
                            Text("No se pudo cargar el audio")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.orange.opacity(0.95))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    durationColumn
                }
            }
            .buttonStyle(.plain)
            .disabled(isPlayLoading)

            metaRow
        }
        .padding(.horizontal, bubblePadH)
        .padding(.vertical, bubblePadV)
        .frame(maxWidth: maxBubbleWidth, alignment: isOutgoing ? .trailing : .leading)
        .background {
            if isOutgoing {
                shape.fill(outgoingBubbleGradient)
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

    private var waveformStrip: some View {
        GeometryReader { geo in
            waveformStripContent(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: waveformStripHeight)
    }

    @ViewBuilder
    private func waveformStripContent(width: CGFloat, height: CGFloat) -> some View {
        let count = max(1, waveformBars.isEmpty ? 24 : waveformBars.count)
        let gap: CGFloat = 2
        let totalGaps = CGFloat(max(0, count - 1)) * gap
        let barW = max(1.5, (width - totalGaps) / CGFloat(count))

        HStack(alignment: .center, spacing: gap) {
            if isPrefetching && waveformBars.isEmpty {
                ForEach(0 ..< min(24, waveformBarCount), id: \.self) { i in
                    voicePlaceholderBar(index: i, barWidth: barW, maxHeight: height)
                }
            } else {
                ForEach(Array(waveformBars.enumerated()), id: \.offset) { _, amp in
                    WaveformBarView(
                        amplitude: amp,
                        maxHeight: height,
                        barWidth: barW,
                        cornerRadius: min(2, barW * 0.45),
                        color: waveformBarColor(amplitude: amp)
                    )
                }
            }
        }
        .frame(width: width, height: height, alignment: .center)
    }

    private func voicePlaceholderBar(index: Int, barWidth: CGFloat, maxHeight: CGFloat) -> some View {
        let t = 0.22 + 0.55 * (0.5 + 0.5 * sin(Double(index) * 0.38))
        let h = max(4, maxHeight * CGFloat(t))
        let fill = isOutgoing ? Color.white.opacity(0.2) : Color.white.opacity(0.16)
        return RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(fill)
            .frame(width: barWidth, height: h)
    }

    private func waveformBarColor(amplitude: CGFloat) -> Color {
        if isOutgoing {
            let a = Double(amplitude)
            return Color.white.opacity(0.28 + 0.62 * a)
        }
        let a = Double(amplitude)
        return Color(red: 0.75 + 0.2 * a, green: 0.88 + 0.1 * a, blue: 1.0).opacity(0.45 + 0.5 * a)
    }

    @ViewBuilder
    private var durationColumn: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if isPlaying {
                TimelineView(.animation(minimumInterval: 0.12, paused: false)) { _ in
                    let cur = player?.currentTime ?? 0
                    Text(VoiceMessageWaveformExtractor.formatDuration(cur))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isOutgoing ? Color.white : incomingText)
                }
                Text("/ \(VoiceMessageWaveformExtractor.formatDuration(audioDuration))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isOutgoing ? outgoingMeta : incomingMeta)
            } else {
                Text(VoiceMessageWaveformExtractor.formatDuration(audioDuration))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isOutgoing ? Color.white : incomingText)
            }
        }
        .frame(minWidth: 44, alignment: .trailing)
    }

    @ViewBuilder
    private var metaRow: some View {
        if isOutgoing, let receipt {
            HStack(spacing: 4) {
                Text(time)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(outgoingMeta)
                voiceReceiptMarks(receipt)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            Text(time)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(incomingMeta)
                .frame(maxWidth: .infinity, alignment: .leading)
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
            .foregroundStyle(Color.white.opacity(0.52))
        case .read:
            HStack(spacing: -5) {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(Color.white.opacity(0.92))
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
                VoiceMessageWaveformExtractor.waveformBars(fromM4AData: data, barCount: barN)
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
                    waveformBars = VoiceMessageWaveformExtractor.waveformBars(fromM4AData: data, barCount: waveformBarCount)
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

        if fileExtension == "m4a" || fileExtension == "mp4" || fileExtension == "mp3" || fileExtension == "aac" {
            do {
                let p = try AVAudioPlayer(contentsOf: temp)
                p.prepareToPlay()
                guard p.play() else { throw NSError(domain: "Drflow", code: 3) }
                player = p
                isPlaying = true
                let token = UUID()
                playbackToken = token
                let duration = max(p.duration, 0.35)
                if audioDuration < 0.5 { audioDuration = duration }
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
        tv.textColor = UIColor(white: 0.96, alpha: 1)
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
        tv.textColor = UIColor(white: 0.96, alpha: 1)
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

// MARK: - Fondo conversación (oscuro fijo; el mesh Revolut solo en la lista de chats)

private struct ConversationBackdrop: View {
    private static let base = Color(red: 4 / 255, green: 4 / 255, blue: 7 / 255)

    var body: some View {
        ZStack {
            Self.base
            LinearGradient(
                colors: [
                    Color.black.opacity(0.55),
                    Color.black.opacity(0.12),
                    Color.black.opacity(0.62),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

#Preview {
    NavigationStack {
        ChatConversationView(thread: ChatThread.samples[0])
            .environmentObject(ChatInboxStore())
            .environmentObject(DashboardCommunityViewModel())
            .environmentObject(AuthViewModel())
    }
}
