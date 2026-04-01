import SwiftUI
import PhotosUI
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

private struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String?
    let image: UIImage?
    let isOutgoing: Bool
    let time: String
    /// Solo salientes; `nil` en entrantes.
    let receipt: OutgoingReceipt?

    init(text: String, isOutgoing: Bool, time: String, receipt: OutgoingReceipt? = nil) {
        self.text = text; self.image = nil
        self.isOutgoing = isOutgoing; self.time = time
        self.receipt = isOutgoing ? (receipt ?? .read) : nil
    }

    init(image: UIImage, isOutgoing: Bool, time: String, receipt: OutgoingReceipt? = nil) {
        self.text = nil; self.image = image
        self.isOutgoing = isOutgoing; self.time = time
        self.receipt = isOutgoing ? (receipt ?? .read) : nil
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

    /// Mismos márgenes que el scroll (sincroniza la barra inferior al salir del GeometryReader).
    @State private var inputBarHorizontalPadding = ChatHorizontalPadding(leading: 20, trailing: 20)

    private var mockMsgs: [ChatMessage] {
        Self.mockMessages(for: thread)
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
        "chat-bottom-\(thread.id.uuidString)-\(liveMessages.count)-\(chatInbox.coordinatorTimelineTick)"
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
                            ForEach(mockMsgs) { msg in
                                messageBubble(msg, maxBubbleWidth: maxBubble)
                                    .frame(maxWidth: innerW)
                                    .id(msg.id)
                            }
                            if thread.kind == .teamDirect {
                                ForEach(chatInbox.coordinatorTasks(forPeer: thread.id)) { task in
                                    coordinatorTaskCard(task, maxBubbleWidth: maxBubble, innerW: innerW)
                                        .id(task.id)
                                }
                            }
                            ForEach(liveMessages) { msg in
                                messageBubble(msg, maxBubbleWidth: maxBubble)
                                    .frame(maxWidth: innerW)
                                    .id(msg.id)
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
                    .onChange(of: liveMessages.count) { _, _ in
                        scrollChatToBottom(proxy: proxy)
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
            chatInbox.markThreadAsRead(thread.id)
        }
    }

    /// Mismos márgenes horizontales que el hilo de mensajes (atrás / avatar).
    private func inputBarChrome(leadingPad: CGFloat, trailingPad: CGFloat) -> some View {
        messageInputBar
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
                if let image = msg.image {
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

    private func coordinatorTaskCard(_ task: CoordinatorOutboundTask, maxBubbleWidth: CGFloat, innerW: CGFloat) -> some View {
        let peerId = thread.peerUserId ?? thread.id
        return HStack {
            Spacer(minLength: bubbleEdgeMargin)
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
                Text(task.body)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(incomingBubbleTextColor)
                    .fixedSize(horizontal: false, vertical: true)

                if task.acceptedAt == nil {
                    Button {
                        chatInbox.acceptCoordinatorTask(peerUserId: peerId, taskId: task.id)
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
                            peerUserId: peerId,
                            taskId: task.id,
                            step: step
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
                    if draftIsEmpty {
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
                .disabled(draftIsEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, composerVerticalPadding)
            .frame(maxWidth: .infinity, minHeight: AppChromeHeaderMetrics.circleButtonSize, alignment: .center)
            .background {
                DashboardChromeCardBackground(cornerRadius: composerChromeCorner)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: draftIsEmpty)
        .animation(.easeInOut(duration: 0.2), value: draft.count)
    }

    // MARK: - Envío texto

    private func sendMessage() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let now = Self.currentTimeString()
        withAnimation {
            liveMessages.append(ChatMessage(text: text, isOutgoing: true, time: now, receipt: .sent))
        }
        draft = ""
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

// MARK: - Prueba de tarea (coordinador IA)

private struct CoordinatorTaskStepProofRow: View {
    @EnvironmentObject private var chatInbox: ChatInboxStore
    let peerUserId: UUID
    let taskId: UUID
    let step: CoordinatorTaskStep
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
                            peerUserId: peerUserId,
                            taskId: taskId,
                            stepId: step.id,
                            imageData: jpeg
                        )
                        pickerItem = nil
                    }
                }
            }

            Button {
                chatInbox.verifyCoordinatorStep(peerUserId: peerUserId, taskId: taskId, stepId: step.id)
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
