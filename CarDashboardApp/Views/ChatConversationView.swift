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
    /// Ruta en bucket `team_direct_voice` (prefijo en fila `body`).
    let voiceStoragePath: String?
    let isOutgoing: Bool
    let time: String
    /// Orden cronológico respecto a tareas del coordinador y otros mensajes.
    let sortKey: Date
    /// Solo salientes; `nil` en entrantes.
    let receipt: OutgoingReceipt?

    init(
        id: UUID = UUID(),
        text: String,
        isOutgoing: Bool,
        time: String,
        receipt: OutgoingReceipt? = nil,
        sortKey: Date = Date(),
        voiceStoragePath: String? = nil
    ) {
        self.id = id
        self.text = text
        self.image = nil
        self.voiceStoragePath = voiceStoragePath
        self.isOutgoing = isOutgoing
        self.time = time
        self.sortKey = sortKey
        self.receipt = isOutgoing ? (receipt ?? .read) : nil
    }

    init(
        id: UUID = UUID(),
        image: UIImage,
        isOutgoing: Bool,
        time: String,
        receipt: OutgoingReceipt? = nil,
        sortKey: Date = Date(),
        voiceStoragePath: String? = nil
    ) {
        self.id = id
        self.text = nil
        self.image = image
        self.voiceStoragePath = voiceStoragePath
        self.isOutgoing = isOutgoing
        self.time = time
        self.sortKey = sortKey
        self.receipt = isOutgoing ? (receipt ?? .read) : nil
    }

    init(
        id: UUID,
        voiceStoragePath: String,
        isOutgoing: Bool,
        time: String,
        receipt: OutgoingReceipt?,
        sortKey: Date
    ) {
        self.id = id
        self.text = nil
        self.image = nil
        self.voiceStoragePath = voiceStoragePath
        self.isOutgoing = isOutgoing
        self.time = time
        self.sortKey = sortKey
        self.receipt = isOutgoing ? (receipt ?? .read) : nil
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

/// DM equipo: un solo hilo temporal (mensajes + tarjetas de tarea Viera).
private enum TeamDirectTimelineItem: Identifiable {
    case message(ChatMessage)
    case coordinatorTask(CoordinatorOutboundTask)

    var id: UUID {
        switch self {
        case .message(let m): return m.id
        case .coordinatorTask(let t): return t.id
        }
    }

    var sortKey: Date {
        switch self {
        case .message(let m): return m.sortKey
        case .coordinatorTask(let t): return t.createdAt ?? .distantPast
        }
    }
}

// MARK: - Vista de conversación

struct ChatConversationView: View {
    let thread: ChatThread

    @EnvironmentObject private var chatInbox: ChatInboxStore
    @EnvironmentObject private var communityVM: DashboardCommunityViewModel
    @EnvironmentObject private var auth: AuthViewModel
    @State private var liveMessages: [ChatMessage] = []
    @State private var draft = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var teamDirectRows: [TeamDirectMessagesService.Row] = []
    @State private var teamDirectChannel: RealtimeChannelV2?
    @State private var teamDirectLoadError: String?
    @State private var teamGroupRows: [TeamGroupMessagesService.Row] = []
    @State private var teamGroupChannel: RealtimeChannelV2?
    @State private var teamGroupLoadError: String?
    @State private var deadlineEditTask: CoordinatorOutboundTask?
    @State private var deadlineEditValue = Date()

    /// Mismos márgenes que el scroll (sincroniza la barra inferior al salir del GeometryReader).
    @State private var inputBarHorizontalPadding = ChatHorizontalPadding(leading: 20, trailing: 20)

    @StateObject private var chatDictationTranscriber = LiveSpeechTranscriber()
    @State private var isChatDictating = false
    @State private var isRecordingTeamVoice = false
    @State private var teamVoiceRecorder: AVAudioRecorder?
    @State private var teamVoiceURL: URL?
    @State private var teamVoiceError: String?

    private var mockMsgs: [ChatMessage] {
        Self.mockMessages(for: thread)
    }

    private var usesTeamDirectServer: Bool {
        thread.kind == .teamDirect && thread.peerUserId != nil && auth.session != nil
    }

    private var usesTeamGroupServer: Bool {
        thread.kind == .teamGroup && auth.session != nil
    }

    private var stackedConversationMessages: [ChatMessage] {
        if usesTeamGroupServer { return teamGroupUIMessages + liveMessages }
        if usesTeamDirectServer { return teamDirectUIMessages + liveMessages }
        return mockMsgs + liveMessages
    }

    private var teamDirectUIMessages: [ChatMessage] {
        guard let myId = auth.session?.user.id else { return [] }
        return teamDirectRows.map { Self.chatMessage(from: $0, myUserId: myId) }
    }

    private var teamGroupUIMessages: [ChatMessage] {
        guard let myId = auth.session?.user.id else { return [] }
        return teamGroupRows.map {
            Self.chatMessageGroup(from: $0, myUserId: myId, directory: communityVM.directory)
        }
    }

    /// Mensajes de texto e imágenes mezclados con tareas del coordinador por `created_at` / hora local.
    private var teamDirectTimelineItems: [TeamDirectTimelineItem] {
        guard usesTeamDirectServer,
              let myId = auth.session?.user.id,
              let otherId = thread.peerUserId
        else { return [] }
        let msgs = teamDirectUIMessages + liveMessages
        let tasks = chatInbox.coordinatorTasksInTeamDirectThread(myUserId: myId, otherUserId: otherId)
        var items: [TeamDirectTimelineItem] = msgs.map { .message($0) }
            + tasks.map { .coordinatorTask($0) }
        items.sort {
            if $0.sortKey != $1.sortKey {
                return $0.sortKey < $1.sortKey
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        return items
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
        }
    }

    /// Cabecera conversación: título blanco y estado en gris más marcado.
    private let chatToolbarNameColor = Color.white
    private let chatToolbarStatusColor = Color(red: 0.62, green: 0.66, blue: 0.72)
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
        return "chat-bottom-\(thread.id.uuidString)-\(count)-\(chatInbox.coordinatorTimelineTick)"
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
                            if usesTeamDirectServer,
                               let myId = auth.session?.user.id,
                               thread.peerUserId != nil
                            {
                                ForEach(teamDirectTimelineItems) { item in
                                    switch item {
                                    case .message(let msg):
                                        messageBubble(msg, maxBubbleWidth: maxBubble)
                                            .frame(maxWidth: innerW)
                                            .id(msg.id)
                                    case .coordinatorTask(let task):
                                        coordinatorTaskCard(task, myUserId: myId, maxBubbleWidth: maxBubble, innerW: innerW)
                                            .id(task.id)
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
                    .onChange(of: chatInbox.coordinatorTimelineTick) { _, _ in
                        scrollChatToBottom(proxy: proxy)
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
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(thread.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(chatToolbarNameColor)
                        .lineLimit(1)
                    Text(conversationStatusLine)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(chatToolbarStatusColor)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .background {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.65)
                        }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                conversationAvatar
            }
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
                break
            }
        }
        .onChange(of: deadlineEditTask) { _, task in
            if let task {
                deadlineEditValue = task.deadline
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
        .sheet(item: $deadlineEditTask) { task in
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Nuevo plazo")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    DatePicker(
                        "Límite",
                        selection: $deadlineEditValue,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    Button {
                        guard let uid = auth.session?.user.id else { return }
                        let tid = task.id
                        let picked = deadlineEditValue
                        Task {
                            try? await chatInbox.updateCoordinatorTaskDeadline(
                                taskId: tid,
                                newDeadline: picked,
                                currentUserId: uid
                            )
                            await MainActor.run { deadlineEditTask = nil }
                        }
                    } label: {
                        Text("Guardar")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(20)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { deadlineEditTask = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    /// Mismos márgenes horizontales que el hilo de mensajes (atrás / avatar).
    private func inputBarChrome(leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        VStack(spacing: 6) {
            if isRecordingTeamVoice {
                Text("Suelta para enviar la nota de voz")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.cyan.opacity(0.88))
            }
            messageInputBar
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .padding(.leading, leadingPad)
        .padding(.trailing, trailingPad)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    // MARK: - Avatar (derecha toolbar)

    private var conversationAvatar: some View {
        ChatInboxListAvatarView(
            thread: thread,
            directory: communityVM.directory,
            accessToken: auth.session?.accessToken,
            currentUserId: auth.session?.user.id,
            localProfileImage: auth.profileAvatarImage,
            localInitials: auth.userInitials,
            diameter: 38
        )
        .overlay {
            Circle()
                .strokeBorder(Color.white.opacity(0.92), lineWidth: 2)
        }
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
                    teamDirectVoiceBubble(
                        storagePath: voicePath,
                        msg: msg,
                        maxBubbleWidth: maxBubbleWidth
                    )
                } else if let image = msg.image {
                    outgoingOrIncomingImageBubble(msg, image: image, maxBubbleWidth: maxBubbleWidth)
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
    }

    private func teamDirectVoiceBubble(storagePath: String, msg: ChatMessage, maxBubbleWidth: CGFloat) -> some View {
        TeamDirectVoiceBubbleView(
            storagePath: storagePath,
            isOutgoing: msg.isOutgoing,
            time: msg.time,
            receipt: msg.receipt,
            maxBubbleWidth: maxBubbleWidth
        )
    }

    private func incomingTextBubble(text: String, time: String, maxBubbleWidth: CGFloat) -> some View {
        let contentCap = max(40, maxBubbleWidth - 2 * bubblePadH - 4)
        let shape = RoundedRectangle(cornerRadius: bubbleCorner, style: .continuous)

        return Group {
            if chatTextFitsSingleLineWithMeta(text: text, time: time, maxBubbleWidth: maxBubbleWidth, outgoing: false, receipt: nil) {
                HStack(alignment: .bottom, spacing: 6) {
                    Text(text)
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
                incomingTextMultiline(text: text, time: time, contentCap: contentCap, shape: shape)
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

    // MARK: - Tareas del coordinador IA (DM equipo)

    private func coordinatorTaskCard(_ task: CoordinatorOutboundTask, myUserId: UUID, maxBubbleWidth: CGFloat, innerW: CGFloat) -> some View {
        let recipientKey = task.peerUserId
        let isAssignee = myUserId == task.peerUserId
        let isSender = myUserId == task.senderUserId
        let deadlineText = Self.coordinatorTaskDeadlineFormatter.string(from: task.deadline)
        let overdue = task.deadline < Date() && !task.isComplete
        /// Alineado al borde izquierdo del hilo (como burbujas entrantes), no centrado entre dos Spacer.
        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.cyan.opacity(0.95))
                    Text("Coordinador IA · Tarea")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.cyan.opacity(0.9))
                }
                Text(task.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(incomingBubbleTextColor)
                HStack(spacing: 6) {
                    Image(systemName: overdue ? "exclamationmark.circle.fill" : "clock")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Límite: \(deadlineText)")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(overdue ? Color.orange.opacity(0.95) : incomingBubbleMetaColor)
                if isSender {
                    Button {
                        deadlineEditTask = task
                    } label: {
                        Text("Cambiar plazo")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.cyan.opacity(0.95))
                    }
                    .buttonStyle(.plain)
                }
                if let ref = task.referenceImageData, let ui = UIImage(data: ref) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Vehículo de referencia")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(incomingBubbleMetaColor)
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 168)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                            }
                    }
                }
                Text(task.body)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(incomingBubbleTextColor)
                    .fixedSize(horizontal: false, vertical: true)

                if task.acceptedAt == nil, isAssignee {
                    Button {
                        chatInbox.acceptCoordinatorTask(recipientUserId: recipientKey, taskId: task.id)
                    } label: {
                        Text("Aceptar tarea")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.cyan.opacity(0.42))
                            }
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Pruebas a entregar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(incomingBubbleMetaColor)
                    ForEach(task.steps) { step in
                        CoordinatorTaskStepProofRow(
                            recipientUserId: recipientKey,
                            taskId: task.id,
                            step: step,
                            canAttachProof: isAssignee,
                            canVerifyProof: isSender
                        )
                    }
                    if task.isComplete {
                        Label("Tarea completada — todas las pruebas validadas", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.green.opacity(0.95))
                            .padding(.top, 2)
                    }
                }

                Text(Self.currentTimeString())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(incomingBubbleMetaColor)
            }
            .frame(maxWidth: maxBubbleWidth, alignment: .leading)
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: bubbleCorner, style: .continuous)
                    .fill(incomingBubbleFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: bubbleCorner, style: .continuous)
                            .strokeBorder(Color.cyan.opacity(0.38), lineWidth: 1)
                    }
            }
            Spacer(minLength: bubbleEdgeMargin)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxWidth: innerW, alignment: .leading)
    }

    // MARK: - Barra de entrada unificada

    private let composerFontSize: CGFloat = 17
    /// Radio fijo: con texto multilínea no parece “cápsula” vertical; mismo lenguaje que tarjetas cromadas.
    private let composerChromeCorner: CGFloat = 22
    private let composerSendBlue = Color(red: 0.0, green: 0.48, blue: 1.0)
    private let composerVerticalPadding: CGFloat = 5
    /// Insets simétricos: la línea queda centrada en el UITextView; el marco exterior centra en los 44 pt.
    private let composerTextTopInset: CGFloat = 2
    private let composerTextBottomInset: CGFloat = 2

    /// ~mitad de pantalla: el texto hace scroll dentro si supera este alto.
    private var composerTextScrollMaxHeight: CGFloat {
        let h = UIScreen.main.bounds.height
        return max(120, h * 0.42)
    }

    private var messageInputBar: some View {
        HStack(alignment: .bottom, spacing: AppChromeHeaderMetrics.hStackSpacing) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                ZStack {
                    DashboardChromeHeaderCircleBackground(size: AppChromeHeaderMetrics.circleButtonSize)
                    Image(systemName: "paperclip")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                }
                .contentShape(Circle())
            }
            .buttonStyle(ChromeCirclePressButtonStyle())
            .disabled(isChatDictating || isRecordingTeamVoice)

            HStack(alignment: .bottom, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    ComposerTextView(
                        text: $draft,
                        maxHeight: composerTextScrollMaxHeight,
                        fontSize: composerFontSize,
                        textTopInset: composerTextTopInset,
                        textBottomInset: composerTextBottomInset
                    )
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity((isChatDictating || isRecordingTeamVoice) ? 0.2 : 1)

                    if isRecordingTeamVoice {
                        Text("Grabando audio…")
                            .font(.system(size: composerFontSize))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.top, composerTextTopInset)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .allowsHitTesting(false)
                    } else if isChatDictating {
                        Group {
                            if chatDictationTranscriber.partialText.isEmpty {
                                Text("Escuchando…")
                                    .font(.system(size: composerFontSize))
                                    .foregroundStyle(.white.opacity(DashboardChromeSearchFieldStyle.promptOpacity))
                            } else {
                                Text(chatDictationTranscriber.partialText)
                                    .font(.system(size: composerFontSize))
                                    .foregroundStyle(.white.opacity(0.92))
                            }
                        }
                        .padding(.top, composerTextTopInset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .allowsHitTesting(false)
                    } else if draftIsEmpty && !isRecordingTeamVoice {
                        Text("Mensaje")
                            .font(.system(size: composerFontSize))
                            .foregroundStyle(.white.opacity(DashboardChromeSearchFieldStyle.promptOpacity))
                            .padding(.top, composerTextTopInset)
                            .allowsHitTesting(false)
                    }
                }

                if !draft.isEmpty {
                    Button {
                        draft = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(.white.opacity(DashboardChromeSearchFieldStyle.iconClearOpacity))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ChromeSmallCirclePressButtonStyle(diameter: 28))
                    .accessibilityLabel("Limpiar mensaje")
                }

                Button { sendMessage() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background {
                            Circle()
                                .fill(draftIsEmpty ? Color.white.opacity(0.14) : composerSendBlue)
                        }
                }
                .buttonStyle(ChromeSmallCirclePressButtonStyle(diameter: 28))
                .disabled(draftIsEmpty || isChatDictating || isRecordingTeamVoice)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, composerVerticalPadding)
            .frame(maxWidth: .infinity, minHeight: AppChromeHeaderMetrics.circleButtonSize, alignment: .center)
            .background {
                DashboardChromeCardBackground(cornerRadius: composerChromeCorner)
            }

            Group {
                if usesTeamDirectServer {
                    TeamDirectMicGestureControl(
                        isDictating: isChatDictating,
                        isRecordingVoice: isRecordingTeamVoice,
                        onStopDictation: { stopChatDictationIfNeeded() },
                        onShortTap: { toggleChatDictation() },
                        onHoldBegan: {
                            Task { @MainActor in
                                await startTeamVoiceNoteRecording()
                            }
                        },
                        onHoldEnded: {
                            Task { @MainActor in
                                await finishTeamVoiceNoteRecordingAndSend()
                            }
                        }
                    )
                } else {
                    Button {
                        toggleChatDictation()
                    } label: {
                        ZStack {
                            DashboardChromeHeaderCircleBackground(size: AppChromeHeaderMetrics.circleButtonSize)
                            Image(systemName: isChatDictating ? "stop.fill" : "mic.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.95))
                        }
                        .contentShape(Circle())
                    }
                    .buttonStyle(ChromeCirclePressButtonStyle())
                    .accessibilityLabel(isChatDictating ? "Detener dictado" : "Dictar mensaje")
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: draftIsEmpty)
        .animation(.easeInOut(duration: 0.2), value: draft.count)
        .animation(.easeInOut(duration: 0.2), value: isChatDictating)
        .animation(.easeInOut(duration: 0.2), value: isRecordingTeamVoice)
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

    @MainActor
    private func startTeamVoiceNoteRecording() async {
        guard usesTeamDirectServer, thread.peerUserId != nil, auth.session != nil else { return }
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
            try av.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
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
                throw NSError(domain: "CarHub", code: 2, userInfo: [NSLocalizedDescriptionKey: "No se pudo grabar audio."])
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
        guard isRecordingTeamVoice else { return }
        teamVoiceRecorder?.stop()
        teamVoiceRecorder = nil
        isRecordingTeamVoice = false
        guard let url = teamVoiceURL, let peer = thread.peerUserId, let myId = auth.session?.user.id else {
            if let u = teamVoiceURL { try? FileManager.default.removeItem(at: u) }
            teamVoiceURL = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        teamVoiceURL = nil
        defer {
            try? FileManager.default.removeItem(at: url)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let nbytes = attrs[.size] as? UInt64,
              nbytes > 400 else {
            return
        }
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
        } catch {
            teamVoiceError = error.localizedDescription
        }
    }

    // MARK: - Envío texto

    private func sendMessage() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
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
                    }
                } catch {
                    await MainActor.run { draft = text }
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

    @MainActor
    private func mergeTeamDirectInsert(_ row: TeamDirectMessagesService.Row) {
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
        await chatInbox.refreshCoordinatorTasksFromServer(currentUserId: myId)
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
                sortKey: sortKey
            )
        }
        return ChatMessage(id: row.id, text: row.body, isOutgoing: outgoing, time: time, receipt: receipt, sortKey: sortKey)
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
            displayText = "\(name): \(row.body)"
        }
        let time = formatChatTime(iso: row.createdAt)
        let sortKey = TeamGroupMessagesService.parseCreatedAt(row.createdAt) ?? Date()
        return ChatMessage(
            id: row.id,
            text: displayText,
            isOutgoing: outgoing,
            time: time,
            receipt: outgoing ? .sent : nil,
            sortKey: sortKey
        )
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

    private static let coordinatorTaskDeadlineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

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
                ChatMessage(text: "Hola, vi el XC60 en Instagram. ¿Sigue disponible?", isOutgoing: false, time: "9:38"),
                ChatMessage(text: "Sí, lo tienes reservado. Mañana lo dejamos impecable.", isOutgoing: true, time: "9:39", receipt: .read),
                ChatMessage(text: "El Volvo está listo para entrega en el concesionario.", isOutgoing: false, time: "9:42")
            ]
        case "10000000-0000-0000-0000-000000000002":
            return [
                ChatMessage(text: "Buenas, me interesa el RS6 del anuncio.", isOutgoing: false, time: "Ayer 18:02"),
                ChatMessage(text: "Hola, te paso condiciones y cuota orientativa.", isOutgoing: true, time: "Ayer 18:10", receipt: .read),
                ChatMessage(text: "¿Sigues con el RS6 publicado? Me interesa financiación.", isOutgoing: false, time: "Ayer 18:20"),
                ChatMessage(text: "Sí, cuando quieras te mando simulación.", isOutgoing: true, time: "Ayer 18:22", receipt: .read)
            ]
        case "10000000-0000-0000-0000-000000000003":
            return [
                ChatMessage(text: "Hola, ¿en qué podemos ayudarte?", isOutgoing: false, time: "10:12"),
                ChatMessage(text: "¿Podemos ver el Serie 3 el jueves por la tarde?", isOutgoing: false, time: "10:14"),
                ChatMessage(text: "Perfecto, te agendo a las 17:30.", isOutgoing: true, time: "10:18", receipt: .read)
            ]
        case "10000000-0000-0000-0000-000000000004":
            return [
                ChatMessage(text: "No veíamos el Cupra Formentor en el panel tras la importación.", isOutgoing: false, time: "18/03"),
                ChatMessage(text: "Ya está sincronizado. ¿Lo ves ahora?", isOutgoing: true, time: "18/03", receipt: .read),
                ChatMessage(text: "Sí, todo correcto. Gracias.", isOutgoing: false, time: "18/03")
            ]
        case "10000000-0000-0000-0000-000000000005":
            return [
                ChatMessage(text: "Bienvenido al asistente DealCar. Escribe *stock* o *cita*.", isOutgoing: false, time: "15/03"),
                ChatMessage(text: "/start", isOutgoing: true, time: "15/03", receipt: .delivered)
            ]
        case "10000000-0000-0000-0000-000000000006":
            return [
                ChatMessage(text: "Integración financiación — dealerId para el Mustang.", isOutgoing: false, time: "4:20"),
                ChatMessage(text: "const dealerId = process.env.DEALCAR_DEALER_ID ?? \"b7c179e3…\"", isOutgoing: false, time: "4:23"),
                ChatMessage(text: "Recibido, lo revisamos en staging.", isOutgoing: true, time: "4:25", receipt: .read)
            ]
        case "10000000-0000-0000-0000-000000000007":
            return [
                ChatMessage(text: "Hola, el 320d sigue en venta?", isOutgoing: false, time: "mar 11:02"),
                ChatMessage(text: "Sí, disponible. ¿Quieres más fotos?", isOutgoing: true, time: "mar 11:08", receipt: .read),
                ChatMessage(text: "¿Sigue disponible el 320d? Puedo pasar mañana.", isOutgoing: false, time: "mar 18:40")
            ]
        case "10000000-0000-0000-0000-000000000008":
            return [
                ChatMessage(text: "Interesado en el A4 del Marketplace.", isOutgoing: false, time: "lun 9:05"),
                ChatMessage(text: "Te dejo el enlace al informe CARFAX del A4.", isOutgoing: false, time: "lun 9:12"),
                ChatMessage(text: "Gracias, lo miro y te digo.", isOutgoing: true, time: "lun 9:20", receipt: .read)
            ]
        default:
            return [
                ChatMessage(text: "Hola, ¿en qué podemos ayudarte?", isOutgoing: false, time: "10:12"),
                ChatMessage(text: "Gracias, os escribo desde la app del concesionario.", isOutgoing: true, time: "10:18", receipt: .read)
            ]
        }
    }
}

// MARK: - Mic DM equipo (toca = dictado, mantén = nota de voz)

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

// MARK: - Burbuja nota de voz (Storage)

private struct TeamDirectVoiceBubbleView: View {
    let storagePath: String
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
    @State private var playbackToken = UUID()
    @State private var playFileURL: URL?

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
        .task(id: storagePath) {
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
        let path = storagePath
        do {
            let data = try await TeamDirectVoiceStorage.download(
                path: path,
                client: SupabaseClientProvider.shared
            )
            let barN = waveformBarCount
            let bars = await Task.detached(priority: .userInitiated) {
                VoiceMessageWaveformExtractor.waveformBars(fromM4AData: data, barCount: barN)
            }.value
            let dur = VoiceMessageWaveformExtractor.durationSeconds(ofM4AData: data) ?? 0
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
                    try playData(data)
                } catch {
                    loadFailed = true
                }
            }
            return
        }
        isPlayLoading = true
        let path = storagePath
        Task {
            do {
                let data = try await TeamDirectVoiceStorage.download(
                    path: path,
                    client: SupabaseClientProvider.shared
                )
                await MainActor.run {
                    cachedAudioData = data
                    waveformBars = VoiceMessageWaveformExtractor.waveformBars(fromM4AData: data, barCount: waveformBarCount)
                    audioDuration = VoiceMessageWaveformExtractor.durationSeconds(ofM4AData: data) ?? 0
                    isPlayLoading = false
                    do {
                        try playData(data)
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
        isPlaying = false
        playbackToken = UUID()
        if let url = playFileURL {
            try? FileManager.default.removeItem(at: url)
            playFileURL = nil
        }
    }

    @MainActor
    private func playData(_ data: Data) throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try AVAudioSession.sharedInstance().setActive(true)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("dm-play-\(UUID().uuidString).m4a")
        try data.write(to: temp)
        playFileURL = temp
        let p = try AVAudioPlayer(contentsOf: temp)
        p.prepareToPlay()
        guard p.play() else {
            throw NSError(domain: "CarHub", code: 3, userInfo: [NSLocalizedDescriptionKey: "Reproducción no disponible."])
        }
        player = p
        isPlaying = true
        let token = UUID()
        playbackToken = token
        let duration = max(p.duration, 0.35)
        if audioDuration < 0.5 {
            audioDuration = duration
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64((duration + 0.15) * 1_000_000_000))
            guard playbackToken == token else { return }
            stopPlaybackCleanup()
        }
    }
}

// MARK: - Prueba de tarea (coordinador IA)

private struct CoordinatorTaskStepProofRow: View {
    @EnvironmentObject private var chatInbox: ChatInboxStore
    let recipientUserId: UUID
    let taskId: UUID
    let step: CoordinatorTaskStep
    var canAttachProof: Bool = true
    var canVerifyProof: Bool = true
    @State private var pickerItem: PhotosPickerItem?

    private let instructionColor = Color.white
    private let rowStroke = Color.white.opacity(0.12)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text(step.instruction)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(instructionColor)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if step.verified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.green.opacity(0.95))
                        .accessibilityLabel("Prueba validada")
                }
            }

            if let data = step.proofImageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if canAttachProof {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(step.proofImageData == nil ? "Adjuntar prueba (foto)" : "Cambiar foto", systemImage: "camera.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.14))
                        }
                }
                .disabled(step.verified)
                .onChange(of: pickerItem) { _, newItem in
                    Task {
                        guard let newItem else { return }
                        guard let data = try? await newItem.loadTransferable(type: Data.self),
                              let ui = UIImage(data: data),
                              let jpeg = ui.jpegData(compressionQuality: 0.82) else { return }
                        await MainActor.run {
                            chatInbox.setCoordinatorStepProof(
                                recipientUserId: recipientUserId,
                                taskId: taskId,
                                stepId: step.id,
                                imageData: jpeg
                            )
                            pickerItem = nil
                        }
                    }
                }
            }

            if canVerifyProof {
                Button {
                    chatInbox.verifyCoordinatorStep(recipientUserId: recipientUserId, taskId: taskId, stepId: step.id)
                } label: {
                    Text("Validar prueba con IA")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    (step.proofImageData == nil || step.verified)
                                        ? Color.white.opacity(0.1)
                                        : Color.green.opacity(0.45)
                                )
                        }
                }
                .buttonStyle(.plain)
                .disabled(step.proofImageData == nil || step.verified)
            }
        }
        .padding(11)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(rowStroke, lineWidth: 0.8)
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
