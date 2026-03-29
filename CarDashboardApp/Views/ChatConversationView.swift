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
    @State private var liveMessages: [ChatMessage] = []
    @State private var draft = ""
    @State private var selectedPhoto: PhotosPickerItem?

    /// Mismos márgenes que el scroll (sincroniza la barra inferior al salir del GeometryReader).
    @State private var inputBarHorizontalPadding = ChatHorizontalPadding(leading: 20, trailing: 20)

    private var allMessages: [ChatMessage] {
        Self.mockMessages(for: thread.title) + liveMessages
    }

    private var draftIsEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Colores cabecera conversación (referencia Telegram).
    private let chatToolbarNameColor = Color.black
    private let chatToolbarStatusColor = Color(red: 0.44, green: 0.44, blue: 0.44)

    /// Margen desde el borde seguro hasta el contenido del chat, alineado visualmente con barra de navegación (atrás / avatar ~40pt).
    private let navBarContentInset: CGFloat = 20
    /// Espacio mínimo entre burbuja y el lado opuesto dentro del ancho útil.
    private let bubbleEdgeMargin: CGFloat = 12

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
                            ForEach(allMessages) { msg in
                                messageBubble(msg, maxBubbleWidth: maxBubble)
                                    .frame(maxWidth: innerW)
                                    .id(msg.id)
                            }
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
                    .onChange(of: allMessages.count) { _, _ in
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
                    Text("últ. vez recientemente")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(chatToolbarStatusColor)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color(red: 0.99, green: 0.97, blue: 0.93))
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.95), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.07), radius: 5, x: 0, y: 2)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.75), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.1), radius: 14, x: 0, y: 6)
            }
            .padding(.leading, leadingPad)
            .padding(.trailing, trailingPad)
            .padding(.top, 4)
            .padding(.bottom, 4)
    }

    // MARK: - Avatar (derecha toolbar)

    private var conversationAvatar: some View {
        ChatThreadAvatarView(thread: thread, diameter: 38)
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.92), lineWidth: 2)
            }
    }

    // MARK: - Burbujas

    private let outgoingBubbleFill = Color(red: 0.52, green: 0.78, blue: 0.98)
    private let incomingBubbleFill = Color(white: 0.97)
    /// Hora y checks en salientes (azul tipo referencia).
    private let outgoingMetaTint = Color(red: 0.22, green: 0.52, blue: 0.82)
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
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text(time)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondary)
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
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 0, maxWidth: contentCap, alignment: .leading)

            Text(time)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.secondary)
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
                        .foregroundStyle(.black)
                        .lineLimit(1)
                    outgoingMetaRow(time: time, receipt: receipt)
                }
                .padding(.horizontal, bubblePadH)
                .padding(.vertical, bubblePadV)
                .background { shape.fill(outgoingBubbleFill) }
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
                .foregroundStyle(.black)
                .multilineTextAlignment(.trailing)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 0, maxWidth: contentCap, alignment: .trailing)

            outgoingMetaRow(time: time, receipt: receipt)
                .frame(maxWidth: contentCap, alignment: .trailing)
        }
        .padding(.horizontal, bubblePadH)
        .padding(.vertical, bubblePadV)
        .background { shape.fill(outgoingBubbleFill) }
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
            outgoingDoubleCheckmarks(foreground: Color(white: 0.45))
        case .read:
            outgoingDoubleCheckmarks(foreground: outgoingMetaTint)
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
                    .fill(outgoingBubbleFill)
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
                    .foregroundStyle(Color.secondary)
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

    // MARK: - Barra de entrada unificada

    private let iconGray = Color(red: 0.22, green: 0.24, blue: 0.26)
    private let accentBlue = Color(red: 0.0, green: 0.478, blue: 1.0)

    private let attachmentButtonSize: CGFloat = 36
    private let composerFieldCorner: CGFloat = 20

    /// ~mitad de pantalla: el texto hace scroll dentro si supera este alto.
    private var composerTextScrollMaxHeight: CGFloat {
        let h = UIScreen.main.bounds.height
        return max(100, h * 0.42)
    }

    private var messageInputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Image(systemName: "paperclip")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(iconGray)
                    .frame(width: attachmentButtonSize, height: attachmentButtonSize)
                    .background {
                        Circle()
                            .fill(Color.white.opacity(0.92))
                            .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
                    }
            }
            .buttonStyle(.plain)

            HStack(alignment: .bottom, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    ComposerTextView(text: $draft, maxHeight: composerTextScrollMaxHeight)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                    if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Mensaje")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.secondary)
                            .padding(.top, 7)
                            .allowsHitTesting(false)
                    }
                }

                Button { sendMessage() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background {
                            Circle()
                                .fill(draftIsEmpty ? Color.gray.opacity(0.35) : accentBlue)
                        }
                }
                .buttonStyle(.plain)
                .disabled(draftIsEmpty)
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: attachmentButtonSize, alignment: .bottom)
            .background {
                RoundedRectangle(cornerRadius: composerFieldCorner, style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
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

    /// Baja al último mensaje tras enviar o cargar; `async` para que `LazyVStack` ya tenga la fila.
    private func scrollChatToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        guard let lastId = allMessages.last?.id else { return }
        let scroll = {
            if animated {
                withAnimation(.easeOut(duration: 0.28)) {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
        DispatchQueue.main.async {
            scroll()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                if animated {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                } else {
                    proxy.scrollTo(lastId, anchor: .bottom)
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

    private static func mockMessages(for title: String) -> [ChatMessage] {
        switch title {
        case "Taller central":
            return [
                ChatMessage(text: "Hola, el taller confirma cita para mañana 10:00.", isOutgoing: false, time: "9:38"),
                ChatMessage(text: "Perfecto, llevo el coche entonces.", isOutgoing: true, time: "9:40", receipt: .read),
                ChatMessage(text: "El vehículo está listo para recogida.", isOutgoing: false, time: "9:42")
            ]
        case "María · Ventas":
            return [
                ChatMessage(text: "Buenos días, te paso el PDF del mes.", isOutgoing: false, time: "Ayer 18:02"),
                ChatMessage(text: "Gracias María.", isOutgoing: true, time: "Ayer 18:15", receipt: .read),
                ChatMessage(text: "Te envío el informe de comisiones del mes.", isOutgoing: false, time: "Ayer 18:20"),
                ChatMessage(text: "Cualquier duda me escribes.", isOutgoing: false, time: "Ayer 18:22")
            ]
        case "DealCar Bot":
            return [
                ChatMessage(text: "Bienvenido al asistente DealCar. Escribe *stock* o *cita*.", isOutgoing: false, time: "15/03"),
                ChatMessage(text: "/start", isOutgoing: true, time: "15/03", receipt: .delivered)
            ]
        default:
            return [
                ChatMessage(text: "Hola, ¿en qué podemos ayudarte?", isOutgoing: false, time: "10:12"),
                ChatMessage(text: "Gracias, os escribo desde la app del concesionario.", isOutgoing: true, time: "10:18", receipt: .read)
            ]
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

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> ComposerSizingTextView {
        let tv = ComposerSizingTextView()
        tv.maxComposerHeight = maxHeight
        tv.delegate = context.coordinator
        tv.font = .systemFont(ofSize: 16)
        tv.textColor = .label
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
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

// MARK: - Fondo conversación

private struct ConversationBackdrop: View {
    /// < 1 = motivo más fino / más mosaico.
    private let patternVisualScale: CGFloat = 0.28

    var body: some View {
        ZStack {
            // Degradado tipo Telegram (cian → lima suave) sobre la base
            LinearGradient(
                colors: [
                    Color(red: 0.72, green: 0.88, blue: 0.90),
                    Color(red: 0.82, green: 0.93, blue: 0.82),
                    Color(red: 0.90, green: 0.95, blue: 0.78)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image("ChatBackdropBase")
                .resizable()
                .scaledToFill()
                .opacity(0.35)
                .clipped()

            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height
                let s = patternVisualScale
                Image("ChatBackgroundPattern")
                    .resizable(resizingMode: .tile)
                    .frame(width: w / s, height: h / s)
                    .scaleEffect(s, anchor: .topLeading)
                    .frame(width: w, height: h, alignment: .topLeading)
                    .clipped()
            }
            .allowsHitTesting(false)
            .opacity(0.55)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.08),
                    Color.clear,
                    Color.white.opacity(0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    NavigationStack {
        ChatConversationView(thread: ChatThread.samples[0])
            .environmentObject(ChatInboxStore())
    }
}
