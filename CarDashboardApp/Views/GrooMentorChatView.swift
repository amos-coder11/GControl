import SwiftUI

/// Conversación moderna — burbujas, streaming y compositor unificados.
struct GrooMentorChatView: View {
    @EnvironmentObject private var groo: GrooAppStore
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var tabRouter: MainTabRouter
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var isSending = false
    @State private var streaming = ""
    @State private var showScheduleSheet = false
    @State private var showBudgetSheet = false
    @State private var imageLightboxItem: GrooChatImageLightboxItem?
    @FocusState private var focused: Bool

    private var messages: [GrooChatMessage] {
        groo.activeSession?.messages ?? []
    }

    private var linkedPatient: GrooPatient? {
        guard let patientId = groo.activeSession?.patientId else { return nil }
        return groo.patient(withId: patientId)
    }

    private var firstName: String {
        let n = groo.profile.firstName.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "there" : n
    }

    private var sessionTitle: String {
        guard let title = groo.activeSession?.title else { return "\(GrooBrand.appName) Clinic" }
        if title.hasPrefix("Session") { return "\(GrooBrand.appName) Clinic" }
        return title
    }

    var body: some View {
        ZStack(alignment: .top) {
            messagesScroll

            chatHeader

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
                VStack(spacing: 0) {
                    if let patient = linkedPatient {
                        GrooPatientChatContextPanel(
                            patient: patient,
                            groo: groo,
                            onSchedule: { showScheduleSheet = true },
                            onOpenProfile: {
                                groo.openPatientProfile(patient.id)
                                tabRouter.openPatients()
                            },
                            onBudget: { showBudgetSheet = true }
                        )
                    }
                    GrooChatComposerBar(
                        text: $draft,
                        isSending: isSending,
                        focused: $focused,
                        onSend: { Task { await send(draft) } },
                        showsBlurBackground: false
                    )
                }
                .background {
                    GrooChatTheme.floatingBlurChromeBottom()
                        .ignoresSafeArea(edges: .bottom)
                }
            }
        }
        .background {
            GrooChatWallpaper().ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: linkedPatient?.id)
        .sheet(isPresented: $groo.showPaywall) {
            GrooPremiumPaywallView()
                .environmentObject(groo)
                .environmentObject(auth)
        }
        .sheet(isPresented: $showScheduleSheet) {
            if let patient = linkedPatient {
                GrooScheduleAppointmentSheet(patient: patient, compact: true)
                    .environmentObject(groo)
                    .environmentObject(tabRouter)
            }
        }
        .sheet(isPresented: $showBudgetSheet) {
            if let patient = linkedPatient {
                GrooPatientBudgetSheet(patient: patient)
                    .environmentObject(groo)
            }
        }
        .fullScreenCover(item: $imageLightboxItem) { item in
            GrooChatImageLightbox(item: item)
        }
    }

    /// Espacio reservado para compositor (+ panel paciente).
    private var bottomChromeHeight: CGFloat {
        var h: CGFloat = 72
        if linkedPatient != nil { h += 96 }
        return h
    }

    // MARK: - Header (blur flotante, sin barra sólida)

    private var chatHeader: some View {
        HStack(spacing: 8) {
            Button {
                focused = false
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    if groo.subscription == .trial {
                        Text("\(groo.trialMessagesRemaining)")
                            .font(.system(size: 13, weight: .bold))
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
                Text(sessionTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.9))
                    .lineLimit(1)
                Text(linkedPatient != nil
                     ? (isSending ? "escribiendo…" : "últ. vez recientemente")
                     : (isSending ? "escribiendo…" : "en línea"))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.45))
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background { GrooChatTheme.glassPillBackground() }

            Spacer(minLength: 4)

            Group {
                if let patient = linkedPatient {
                    GrooPatientAvatarView(patient: patient, size: 40)
                } else {
                    GrooChatAvatar(size: 40, showsOnlineRing: true)
                }
            }
            .overlay {
                Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background {
            GrooChatTheme.floatingBlurChrome()
                .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: - Messages

    private var messagesScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 3) {
                    securityBanner
                        .padding(.bottom, 8)

                    if messages.isEmpty && streaming.isEmpty && !isSending {
                        welcomeCard.id("empty")
                    }

                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, msg in
                        if shouldShowDateSeparator(at: index) {
                            GrooChatDatePill(label: formatDateSeparator(msg.createdAt))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }

                        let prev = index > 0 ? messages[index - 1] : nil
                        let next = index + 1 < messages.count ? messages[index + 1] : nil
                        let isFirst = prev?.isUser != msg.isUser
                            || (prev != nil && !Calendar.current.isDate(prev!.createdAt, inSameDayAs: msg.createdAt))
                        let isLast = next?.isUser != msg.isUser
                            || (next != nil && !Calendar.current.isDate(next!.createdAt, inSameDayAs: msg.createdAt))

                        messageRow(msg, isLastInGroup: isLast)
                            .padding(.top, isFirst ? 8 : 2)
                            .id(msg.id)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.96).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }

                    if isSending && streaming.isEmpty {
                        typingRow.id("typing")
                    }

                    if !streaming.isEmpty {
                        incomingRow(text: streaming, time: Date(), isLast: true, streaming: true)
                            .id("stream")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 62)
                .padding(.bottom, bottomChromeHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: streaming) { _, _ in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo("stream", anchor: .bottom)
                }
            }
            .onChange(of: isSending) { _, sending in
                if sending { scrollToBottom(proxy) }
            }
            .onTapGesture { focused = false }
        }
    }

    private var securityBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .semibold))
            Text("Clinic messages are private to your account.")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(GrooChatTheme.metaText)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .padding(.top, 4)
    }

    private var welcomeCard: some View {
        VStack(spacing: 10) {
            GrooChatAvatar(size: 72, showsOnlineRing: true)
            Text("Hey \(firstName) 👋")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text("Ask about appointments, patients, billing, or daily clinic operations.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(GrooChatTheme.metaText)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }

    private func messageRow(_ msg: GrooChatMessage, isLastInGroup: Bool) -> some View {
        Group {
            if msg.isUser {
                HStack {
                    Spacer(minLength: 56)
                    GrooMessageBubbleView(
                        text: msg.text,
                        time: msg.createdAt,
                        isOutgoing: true,
                        isLastInGroup: isLastInGroup,
                        delivery: .read,
                        image: msg.uiImage,
                        onImageTap: msg.uiImage.map { image in
                            { imageLightboxItem = .local(image) }
                        }
                    )
                }
            } else {
                incomingRow(text: msg.text, time: msg.createdAt, isLast: isLastInGroup, streaming: false, image: msg.uiImage)
            }
        }
    }

    private func incomingRow(text: String, time: Date, isLast: Bool, streaming: Bool, image: UIImage? = nil) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            GrooMessageBubbleView(
                text: text,
                time: time,
                isOutgoing: false,
                isLastInGroup: isLast,
                isStreaming: streaming,
                image: image,
                onImageTap: image.map { img in
                    { imageLightboxItem = .local(img) }
                }
            )
            Spacer(minLength: 56)
        }
    }

    private var typingRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            GrooTypingIndicatorBubble()
            Spacer(minLength: 56)
        }
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func shouldShowDateSeparator(at index: Int) -> Bool {
        guard index < messages.count else { return false }
        if index == 0 { return true }
        return !Calendar.current.isDate(messages[index].createdAt, inSameDayAs: messages[index - 1].createdAt)
    }

    private func formatDateSeparator(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        let target: AnyHashable
        if !streaming.isEmpty { target = "stream" }
        else if isSending { target = "typing" }
        else if let last = messages.last?.id { target = last }
        else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }

    // MARK: - Send

    private func send(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let patientId = groo.activeSession?.patientId

        if let patientId,
           text.lowercased().contains("presupuesto") {
            guard groo.appendUserMessage(text, countsAgainstTrial: false) else { return }
            draft = ""
            focused = false
            isSending = true
            try? await Task.sleep(nanoseconds: 350_000_000)
            groo.appendAssistantMessage(
                "He preparado el presupuesto de \(linkedPatient?.fullName ?? "el paciente"). Toca el botón 📄 o «Generar PDF y enviar» para mandarlo por WhatsApp o email."
            )
            isSending = false
            showBudgetSheet = true
            return
        }

        if let patientId,
           let appointmentReply = groo.handleChatPatientAppointmentIfNeeded(text: text, patientId: patientId) {
            guard groo.appendUserMessage(text, countsAgainstTrial: false) else { return }
            draft = ""
            focused = false
            isSending = true
            try? await Task.sleep(nanoseconds: 450_000_000)
            groo.appendAssistantMessage(appointmentReply)
            isSending = false
            return
        }

        if let canned = groo.handleChatReminderIfNeeded(text: text, patientId: patientId) {
            guard groo.appendUserMessage(text, countsAgainstTrial: false) else { return }
            draft = ""
            focused = false
            isSending = true
            try? await Task.sleep(nanoseconds: 450_000_000)
            groo.appendAssistantMessage(canned)
            isSending = false
            return
        }

        guard groo.appendUserMessage(text) else { return }
        draft = ""
        focused = false

        isSending = true
        streaming = ""
        defer { isSending = false }

        let history = (groo.activeSession?.messages ?? []).suffix(16).map {
            (isUser: $0.isUser, text: $0.text)
        }

        do {
            if OpenAIChatClient.isConfigured {
                try await OpenAIChatClient.streamVieraChatReply(
                    conversation: Array(history),
                    dataContextSupplement: groo.mentorContextSupplement(for: groo.activeSession)
                ) { chunk in
                    streaming += chunk
                }
                let finalText = streaming.trimmingCharacters(in: .whitespacesAndNewlines)
                streaming = ""
                if !finalText.isEmpty {
                    groo.appendAssistantMessage(VieraCardsParser.visibleText(from: finalText))
                }
            } else {
                try await Task.sleep(nanoseconds: 700_000_000)
                groo.appendAssistantMessage(localMentorReply(to: text))
            }
        } catch {
            streaming = ""
            groo.appendAssistantMessage(
                "I couldn't reach the assistant right now. \(error.localizedDescription)\n\n" +
                localMentorReply(to: text)
            )
        }
    }

    private func localMentorReply(to text: String) -> String {
        let weak = groo.diagnostic?.pillars.min(by: { $0.average < $1.average })?.pillar.title ?? "Operations"
        return """
        Got it. For your clinic, the area that needs attention most is \(weak).

        What's one concrete step you can take in the next 7 days about "\(text)"?

        If there's a date (appointment, follow-up, sterilization), tell me and I'll set a reminder.
        """
    }
}
