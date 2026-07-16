import SwiftUI

/// Chat mentor GROO — liquid glass, burbujas agrupadas, avatares y animaciones.
struct GrooMentorChatView: View {
    @EnvironmentObject private var groo: GrooAppStore
    @EnvironmentObject private var tabRouter: MainTabRouter
    @EnvironmentObject private var auth: AuthViewModel
    @State private var draft = ""
    @State private var isSending = false
    @State private var streaming = ""
    @State private var chatAppeared = false
    @FocusState private var focused: Bool

    private let quickChips: [(icon: String, title: String)] = [
        ("sparkles", "Next career step"),
        ("bubble.left.and.bubble.right.fill", "Hard conversation"),
        ("hand.raised.fill", "Ask for what I need"),
        ("target", "Focus this week"),
        ("bell.fill", "I have an appointment in 1 hour"),
    ]

    private var messages: [GrooChatMessage] {
        groo.activeSession?.messages ?? []
    }

    private var firstName: String {
        let n = groo.profile.firstName.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "there" : n
    }

    private var showChips: Bool {
        !isSending && streaming.isEmpty && messages.filter(\.isUser).count <= 1
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RevolutBackgroundView()

                VStack(spacing: 0) {
                    chatHeader
                    messagesScroll
                    if showChips {
                        chipsRow
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    composer
                }
                .opacity(chatAppeared ? 1 : 0)
                .offset(x: chatAppeared ? 0 : 24)
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: showChips)
            .onAppear {
                groo.ensureWelcomeSession()
                withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) {
                    chatAppeared = true
                }
            }
            .onDisappear { chatAppeared = false }
            .sheet(isPresented: $groo.showPaywall) {
                GrooPremiumPaywallView()
                    .environmentObject(groo)
                    .environmentObject(auth)
            }
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack(spacing: 10) {
            glassCircleButton(icon: "chevron.left", action: goBackHome)

            Image("GrooCharacter")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .shadow(color: GrooBrand.purple.opacity(0.25), radius: 8, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("GROO")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Circle()
                        .fill(Color(red: 0.2, green: 0.78, blue: 0.45))
                        .frame(width: 7, height: 7)
                    Text("Online")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.2, green: 0.7, blue: 0.42))
                }
                .foregroundStyle(Color.black.opacity(0.9))

                Text("Your AI career mentor")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.45))
            }

            Spacer(minLength: 4)

            if groo.subscription == .trial {
                Button { groo.showPaywall = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(groo.trialMessagesRemaining)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(GrooBrand.purple)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(glassCapsule)
                }
                .buttonStyle(.plain)
            }

            glassCircleButton(icon: "square.and.pencil") {
                groo.startNewSession()
                draft = ""
                streaming = ""
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .bottom) { Color.black.opacity(0.04).frame(height: 0.5) }
                .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: - Messages

    private var messagesScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if messages.isEmpty && streaming.isEmpty && !isSending {
                        emptyState.id("empty")
                    }

                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, msg in
                        let prev = index > 0 ? messages[index - 1] : nil
                        let next = index + 1 < messages.count ? messages[index + 1] : nil
                        let isFirstInGroup = prev?.isUser != msg.isUser
                        let isLastInGroup = next?.isUser != msg.isUser

                        bubble(msg, showAvatar: isLastInGroup, showTime: isLastInGroup)
                            .padding(.top, isFirstInGroup ? 12 : 2)
                            .id(msg.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: msg.isUser ? .trailing : .leading).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }

                    if isSending && streaming.isEmpty {
                        typingIndicator
                            .padding(.top, 12)
                            .id("typing")
                    }

                    if !streaming.isEmpty {
                        assistantBubble(text: streaming, isStreaming: true, showAvatar: true, showTime: false)
                            .padding(.top, 12)
                            .id("stream")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
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

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(GrooBrand.purpleSoft)
                    .frame(width: 100, height: 100)
                Image("GrooCharacter")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
            }
            .shadow(color: GrooBrand.purple.opacity(0.2), radius: 16, y: 6)

            VStack(spacing: 6) {
                Text("Hey \(firstName) 👋")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("I'm here to help with your career.\nWhat's on your mind today?")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.48))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Color.black.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func bubble(_ msg: GrooChatMessage, showAvatar: Bool, showTime: Bool) -> some View {
        Group {
            if msg.isUser {
                userBubble(msg.text, time: msg.createdAt, showAvatar: showAvatar, showTime: showTime)
            } else {
                assistantBubble(text: msg.text, isStreaming: false, showAvatar: showAvatar, showTime: showTime, time: msg.createdAt)
            }
        }
    }

    private func userBubble(_ text: String, time: Date, showAvatar: Bool, showTime: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            Spacer(minLength: 52)

            VStack(alignment: .trailing, spacing: 4) {
                Text(text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .lineSpacing(3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 20,
                            bottomLeadingRadius: 20,
                            bottomTrailingRadius: showAvatar ? 6 : 20,
                            topTrailingRadius: 20,
                            style: .continuous
                        )
                        .fill(
                            LinearGradient(
                                colors: [GrooBrand.purple, Color(red: 0.52, green: 0.14, blue: 0.68)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: GrooBrand.purple.opacity(0.3), radius: 10, y: 4)
                    }

                if showTime {
                    Text(formatTime(time))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.32))
                }
            }

            if showAvatar {
                userAvatar(size: 32)
            } else {
                Color.clear.frame(width: 32, height: 1)
            }
        }
    }

    private func assistantBubble(
        text: String,
        isStreaming: Bool,
        showAvatar: Bool,
        showTime: Bool,
        time: Date = Date()
    ) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if showAvatar {
                grooAvatar(size: 32)
            } else {
                Color.clear.frame(width: 32, height: 1)
            }

            VStack(alignment: .leading, spacing: 4) {
                if showAvatar {
                    Text("GROO")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(GrooBrand.purple.opacity(0.75))
                        .padding(.leading, 4)
                }

                Text(text)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.88))
                    .lineSpacing(4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background {
                        UnevenRoundedRectangle(
                            topLeadingRadius: showAvatar ? 6 : 20,
                            bottomLeadingRadius: 20,
                            bottomTrailingRadius: 20,
                            topTrailingRadius: 20,
                            style: .continuous
                        )
                        .fill(.ultraThinMaterial)
                        .background {
                            UnevenRoundedRectangle(
                                topLeadingRadius: showAvatar ? 6 : 20,
                                bottomLeadingRadius: 20,
                                bottomTrailingRadius: 20,
                                topTrailingRadius: 20,
                                style: .continuous
                            )
                            .fill(Color.white.opacity(0.88))
                        }
                        .overlay {
                            UnevenRoundedRectangle(
                                topLeadingRadius: showAvatar ? 6 : 20,
                                bottomLeadingRadius: 20,
                                bottomTrailingRadius: 20,
                                topTrailingRadius: 20,
                                style: .continuous
                            )
                            .strokeBorder(Color.white.opacity(0.9), lineWidth: 0.8)
                        }
                        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
                    }

                if isStreaming {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.65)
                            .tint(GrooBrand.purple)
                        Text("GROO is thinking…")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(GrooBrand.purple.opacity(0.65))
                    }
                    .padding(.leading, 4)
                } else if showTime {
                    Text(formatTime(time))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.32))
                        .padding(.leading, 4)
                }
            }

            Spacer(minLength: 52)
        }
    }

    private var typingIndicator: some View {
        HStack(alignment: .bottom, spacing: 8) {
            grooAvatar(size: 32)

            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(GrooBrand.purple.opacity(0.5))
                        .frame(width: 7, height: 7)
                        .scaleEffect(isSending ? 1 : 0.6)
                        .animation(
                            .easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15),
                            value: isSending
                        )
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(glassBubbleShape)

            Spacer(minLength: 52)
        }
    }

    // MARK: - Avatars

    private func grooAvatar(size: CGFloat) -> some View {
        Image("GrooCharacter")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
            .shadow(color: GrooBrand.purple.opacity(0.2), radius: 4, y: 1)
    }

    private func userAvatar(size: CGFloat) -> some View {
        Group {
            if let img = auth.profileAvatarImage {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(GrooBrand.purpleSoft)
                    Text(userInitial)
                        .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                        .foregroundStyle(GrooBrand.purple)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
        .shadow(color: GrooBrand.purple.opacity(0.15), radius: 4, y: 1)
    }

    private var userInitial: String {
        let n = groo.profile.firstName.trimmingCharacters(in: .whitespaces)
        let c = String(n.prefix(1)).uppercased()
        return c.isEmpty ? "U" : c
    }

    // MARK: - Chips

    private var chipsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try asking")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.38))
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickChips, id: \.title) { chip in
                        Button {
                            Task { await send(chip.title) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: chip.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(chip.title)
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(GrooBrand.purple)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        Capsule(style: .continuous)
                                            .strokeBorder(GrooBrand.purple.opacity(0.15), lineWidth: 0.8)
                                    }
                                    .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
                            }
                        }
                        .buttonStyle(GrooChatPressStyle())
                        .disabled(isSending)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message GROO…", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focused)
                    .font(.system(size: 15, weight: .medium))
                    .submitLabel(.send)
                    .onSubmit {
                        if canSend && !isSending {
                            Task { await send(draft) }
                        }
                    }

                if !draft.isEmpty {
                    Button { draft = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.black.opacity(0.22))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(
                                focused ? GrooBrand.purple.opacity(0.35) : Color.white.opacity(0.7),
                                lineWidth: focused ? 1.2 : 0.75
                            )
                    }
                    .shadow(color: focused ? GrooBrand.purple.opacity(0.1) : .black.opacity(0.04), radius: 8, y: 2)
            }

            Button {
                Task { await send(draft) }
            } label: {
                Image(systemName: isSending ? "ellipsis" : "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background {
                        Circle()
                            .fill(
                                canSend && !isSending
                                    ? LinearGradient(
                                        colors: [GrooBrand.purple, Color(red: 0.52, green: 0.14, blue: 0.68)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    : LinearGradient(
                                        colors: [Color.black.opacity(0.15), Color.black.opacity(0.12)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                            )
                            .shadow(color: canSend ? GrooBrand.purple.opacity(0.35) : .clear, radius: 8, y: 3)
                    }
            }
            .disabled(!canSend || isSending)
            .buttonStyle(GrooChatPressStyle())
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [Color.white.opacity(0.6), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 1)
                }
                .shadow(color: .black.opacity(0.04), radius: 10, y: -3)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Glass helpers

    private var glassCapsule: some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(GrooBrand.purple.opacity(0.2), lineWidth: 0.8)
            }
            .shadow(color: GrooBrand.purple.opacity(0.1), radius: 6, y: 2)
    }

    private var glassBubbleShape: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.ultraThinMaterial)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.88))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }

    private func glassCircleButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GrooBrand.purple)
                .frame(width: 36, height: 36)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay { Circle().strokeBorder(Color.white.opacity(0.75), lineWidth: 0.7) }
                        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
                }
        }
        .buttonStyle(.plain)
    }

    private func formatTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func goBackHome() {
        focused = false
        withAnimation(.spring(response: 0.48, dampingFraction: 0.84)) {
            chatAppeared = false
            tabRouter.selected = .home
        }
    }

    // MARK: - Send

    private func send(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if let canned = groo.handleChatReminderIfNeeded(text: text) {
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
                    dataContextSupplement: groo.careContextForMentor()
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
                "I couldn't reach the mentor right now. \(error.localizedDescription)\n\n" +
                localMentorReply(to: text)
            )
        }
    }

    private func localMentorReply(to text: String) -> String {
        let d = groo.diagnostic
        let weak = d?.pillars.min(by: { $0.average < $1.average })?.pillar.title ?? "Communication"
        return """
        I hear you. Looking at C.A.R.E+U, your biggest friction right now points to \(weak).

        One question to move forward: if you could take one small, real step in the next 7 days about “\(text)” — what would it be?

        Once you say it, we'll build a simple plan. If there's a date (interview, review, meeting), I can suggest a reminder.
        """
    }
}

private struct GrooChatPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}
