import AVFoundation
import Combine
import SwiftUI
import UIKit

// MARK: - Enrutador de pestañas (mismo módulo que `CarsView` / `DashboardView`)

enum CarHubMainTab: Hashable {
    case home
    case cars
    case chat
    case ai
    case settings
}

@MainActor
final class MainTabRouter: ObservableObject {
    @Published var selected: CarHubMainTab = .home
}

/// Abre un hilo concreto al cambiar a la pestaña Chat (p. ej. grupo «Mi equipo» desde Inicio).
@MainActor
final class ChatNavigationCoordinator: ObservableObject {
    @Published var threadToOpen: ChatThread?
}

// MARK: - Pestañas (TabView nativo iOS 26 + Liquid Glass del sistema)

struct MainTabView: View {
    @StateObject private var tabRouter = MainTabRouter()
    @StateObject private var invoiceHistory = InvoiceHistoryStore()
    @StateObject private var notificationsStore = DashboardNotificationsStore()
    @StateObject private var chatInbox = ChatInboxStore()
    @StateObject private var communityVM = DashboardCommunityViewModel()
    @StateObject private var chatNav = ChatNavigationCoordinator()
    @State private var chatSearchText = ""

    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var carsVM: CarsViewModel

    var body: some View {
        TabView(selection: $tabRouter.selected) {
            Tab("Inicio", systemImage: "house.fill", value: CarHubMainTab.home) {
                NavigationStack {
                    DashboardView()
                }
            }

            Tab("Coches", systemImage: "car.fill", value: CarHubMainTab.cars) {
                NavigationStack {
                    CarsView()
                }
            }

            Tab("Chat", systemImage: "bubble.left.and.bubble.right.fill", value: CarHubMainTab.chat) {
                ChatView(searchText: $chatSearchText)
            }
            .badge(chatInbox.totalUnansweredMessageCount)

            Tab("IA", systemImage: "sparkles", value: CarHubMainTab.ai) {
                TeamAITabView()
            }

            Tab("Ajustes", systemImage: "gearshape.fill", value: CarHubMainTab.settings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .environmentObject(chatInbox)
        .environmentObject(tabRouter)
        .environmentObject(chatNav)
        .environmentObject(communityVM)
        .environmentObject(invoiceHistory)
        .environmentObject(notificationsStore)
        /// Anula el `AccentColor` azul del catálogo: la tab seleccionada debe ser blanca, no azul.
        .accentColor(.white)
        .tint(.white)
        .onAppear {
            MainTabBarAppearance.applyWhiteSelection()
            communityVM.attach(auth: auth)
            communityVM.startPeriodicRefresh()
            Task { await communityVM.refresh() }
        }
        .onDisappear {
            communityVM.stopPeriodicRefresh()
        }
        .onChange(of: auth.session?.user.id) { _, _ in
            communityVM.attach(auth: auth)
            Task { await communityVM.refresh() }
        }
        .toolbarBackground(PremiumAccent.tabBarDockBackgroundGradient, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .tabBarMinimizeBehavior(.onScrollDown)
        .task {
            await carsVM.loadVehicles()
        }
    }
}

// MARK: - Pestaña IA (mismo archivo que MainTabView para evitar «Cannot find TeamAITabView in scope» si falta el .swift en el target)

private enum TeamCoordinatorActionParser {
    static func splitResponse(_ raw: String) -> (
        visible: String,
        sends: [(recipientName: String, message: String)],
        tasks: [(recipientName: String, title: String, body: String, steps: [String])]
    ) {
        let start = "<<<ACTIONS>>>"
        let end = "<<<ENDACTIONS>>>"
        guard let r1 = raw.range(of: start),
              let r2 = raw.range(of: end, range: r1.upperBound ..< raw.endIndex)
        else {
            return (raw.trimmingCharacters(in: .whitespacesAndNewlines), [], [])
        }
        let visible = String(raw[..<r1.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let block = String(raw[r1.upperBound ..< r2.lowerBound])
        var sends: [(String, String)] = []
        var tasks: [(String, String, String, [String])] = []
        for line in block.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            let parts = t.split(separator: "|", omittingEmptySubsequences: false).map {
                String($0).trimmingCharacters(in: .whitespaces)
            }
            guard !parts.isEmpty else { continue }
            let cmd = parts[0].uppercased()
            if cmd == "SEND", parts.count >= 3 {
                sends.append((parts[1], parts[2]))
            } else if cmd == "TASK", parts.count >= 5 {
                let name = parts[1]
                let title = parts[2]
                let body = parts[3]
                let stepLines = parts.dropFirst(4).filter { !$0.isEmpty }
                let steps = stepLines.isEmpty
                    ? ["Adjunta una foto o una nota que documente el encargo."]
                    : stepLines
                tasks.append((name, title, body, steps))
            }
        }
        return (visible, sends, tasks)
    }

    static func resolvePeer(
        named: String,
        directory: [CommunityProfilesService.DirectoryRow]
    ) -> CommunityProfilesService.DirectoryRow? {
        let needle = named.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        return directory.first { row in
            let full = row.resolvedDisplayName.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
                .lowercased()
            if full == needle { return true }
            if full.contains(needle) { return true }
            let first = row.resolvedDisplayName.split(separator: " ").first.map(String.init)?
                .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
                .lowercased()
            return first == needle
        }
    }
}

@MainActor
private final class TeamAIAssistantSession: ObservableObject {
    struct Bubble: Identifiable, Equatable {
        let id: UUID
        let isUser: Bool
        let text: String

        init(id: UUID = UUID(), isUser: Bool, text: String) {
            self.id = id
            self.isUser = isUser
            self.text = text
        }
    }

    @Published var bubbles: [Bubble] = []
    @Published var draft: String = ""
    @Published var liveTranscript: String = ""
    @Published var isRecordingAudio = false
    @Published var isSending = false
    @Published var statusHint: String?

    private let transcriber = LiveSpeechTranscriber()
    private var cancellables = Set<AnyCancellable>()

    init() {
        transcriber.$partialText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.liveTranscript = text
            }
            .store(in: &cancellables)
    }

    func beginVoiceInput() {
        guard !isRecordingAudio else { return }
        statusHint = nil
        isRecordingAudio = true
        liveTranscript = ""
        Task {
            let mic = await requestMicrophonePermission()
            guard mic else {
                await MainActor.run {
                    self.isRecordingAudio = false
                    self.statusHint = "Activa el micrófono en Ajustes para dictar."
                }
                return
            }
            let speech = await transcriber.requestSpeechAuthorization()
            guard speech else {
                await MainActor.run {
                    self.isRecordingAudio = false
                    self.statusHint = "Activa el reconocimiento de voz en Ajustes."
                }
                return
            }
            await MainActor.run {
                do {
                    try self.transcriber.startLiveTranscription()
                } catch {
                    self.isRecordingAudio = false
                    self.statusHint = error.localizedDescription
                }
            }
        }
    }

    func endVoiceInput() {
        let captured = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        transcriber.stopLiveTranscription()
        isRecordingAudio = false
        liveTranscript = ""
        if !captured.isEmpty {
            if draft.isEmpty {
                draft = captured
            } else if draft.hasSuffix(" ") {
                draft += captured
            } else {
                draft += " " + captured
            }
        }
    }

    func send(
        directory: [CommunityProfilesService.DirectoryRow],
        currentUserId: UUID?,
        inbox: ChatInboxStore
    ) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        draft = ""
        bubbles.append(Bubble(isUser: true, text: text))
        isSending = true
        statusHint = nil

        let roster = Self.formatRoster(directory: directory, currentUserId: currentUserId)
        let conversation = bubbles.map { ($0.isUser, $0.text) }

        Task {
            do {
                let raw: String
                if AnthropicContractClient.isConfigured {
                    raw = try await AnthropicContractClient.teamCoordinatorReply(
                        rosterLines: roster,
                        conversation: conversation
                    )
                } else {
                    raw = Self.fallbackReply(userText: text, directory: directory, currentUserId: currentUserId)
                }
                let (visible, sends, tasks) = TeamCoordinatorActionParser.splitResponse(raw)
                await MainActor.run {
                    if !visible.isEmpty {
                        self.bubbles.append(Bubble(isUser: false, text: visible))
                    }
                    for item in sends {
                        guard let row = TeamCoordinatorActionParser.resolvePeer(named: item.recipientName, directory: directory)
                        else { continue }
                        if row.userId != currentUserId {
                            inbox.applyTeamCoordinatorOutreach(peerUserId: row.userId, line: item.message)
                        }
                    }
                    for item in tasks {
                        guard let row = TeamCoordinatorActionParser.resolvePeer(named: item.recipientName, directory: directory)
                        else { continue }
                        if row.userId != currentUserId {
                            inbox.appendCoordinatorTask(
                                peerUserId: row.userId,
                                title: item.title,
                                body: item.body,
                                stepInstructions: item.steps
                            )
                            inbox.applyTeamCoordinatorOutreach(peerUserId: row.userId, line: "Tarea: \(item.title)")
                        }
                    }
                    inbox.syncTeamThreads(from: directory, currentUserId: currentUserId)
                    self.isSending = false
                }
            } catch {
                await MainActor.run {
                    self.statusHint = error.localizedDescription
                    self.isSending = false
                }
            }
        }
    }

    private static func formatRoster(
        directory: [CommunityProfilesService.DirectoryRow],
        currentUserId: UUID?
    ) -> String {
        let lines = directory
            .filter { $0.userId != currentUserId }
            .map(\.resolvedDisplayName)
        if lines.isEmpty {
            return "(Aún no hay otros miembros en el directorio.)"
        }
        return lines.joined(separator: "\n")
    }

    private static func fallbackReply(
        userText: String,
        directory: [CommunityProfilesService.DirectoryRow],
        currentUserId: UUID?
    ) -> String {
        let peers = directory.filter { $0.userId != currentUserId }
        let lower = userText.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES")).lowercased()
        var matched: [(CommunityProfilesService.DirectoryRow, String)] = []
        for row in peers {
            let name = row.resolvedDisplayName
            let fullKey = name.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES")).lowercased()
            var hit = lower.contains(fullKey)
            if !hit {
                for part in name.split(separator: " ") {
                    let p = String(part).folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES")).lowercased()
                    if p.count >= 3, lower.contains(p) { hit = true; break }
                }
            }
            if hit {
                matched.append((row, userText))
            }
        }
        if matched.isEmpty {
            return """
            No he podido enlazar un nombre del equipo con lo que dijiste. \
            Nombres en el directorio: \(peers.map(\.resolvedDisplayName).joined(separator: ", ")).

            Con **ANTHROPIC_API_KEY** configurada interpreto mejor órdenes del tipo «dile a Alberto que…».
            """
        }
        var block = "<<<ACTIONS>>>\n"
        for (row, msg) in matched {
            block += "TASK|\(row.resolvedDisplayName)|Encargo del coordinador|\(msg)|Foto que documente el encargo en el concesionario o zona de trabajo|Nota breve con el resultado o el siguiente paso\n"
        }
        block += "<<<ENDACTIONS>>>"
        return "He creado tareas con aceptación y pruebas para: \(matched.map { $0.0.resolvedDisplayName }.joined(separator: ", ")). Abre el chat de cada compañero en «Equipo en chat» para aceptar y subir cada prueba.\n\n\(block)"
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { ok in
                cont.resume(returning: ok)
            }
        }
    }
}

private enum TeamAIScrollID: Hashable {
    case live
    case typing
    case bubble(UUID)
}

struct TeamAITabView: View {
    @StateObject private var session = TeamAIAssistantSession()
    @EnvironmentObject private var communityVM: DashboardCommunityViewModel
    @EnvironmentObject private var inbox: ChatInboxStore
    @EnvironmentObject private var auth: AuthViewModel

    @FocusState private var composerFocused: Bool

    private let incomingFill = Color(red: 0.12, green: 0.15, blue: 0.20)
    private let outgoingBlue = Color(red: 0.0, green: 0.38, blue: 0.98)

    var body: some View {
        RevolutChromeContainer {
            VStack(spacing: 0) {
                headerRow

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            introBanner

                            ForEach(session.bubbles) { bubble in
                                bubbleRow(bubble)
                                    .id(TeamAIScrollID.bubble(bubble.id))
                            }

                            if session.isRecordingAudio {
                                liveTranscriptionBubble
                                    .id(TeamAIScrollID.live)
                            }

                            if session.isSending {
                                typingRow
                                    .id(TeamAIScrollID.typing)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: session.bubbles.count) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: session.isRecordingAudio) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: session.liveTranscript) { _, _ in
                        if session.isRecordingAudio {
                            scrollToBottom(proxy: proxy, animated: false)
                        }
                    }
                }

                composerBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accentColor(.white)
    }

    private var headerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Coordinador IA")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                Text("Voz en tiempo real · tareas al equipo")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var introBanner: some View {
        Text(
            "Toca el micrófono para empezar a dictar y tócalo otra vez para terminar; el texto se escribe en vivo. "
                + "Pide por ejemplo: «Alberto, mándale un mensaje que capte un Ferrari» — se creará una tarea en su chat: debe aceptarla y subir cada prueba (foto, etc.) paso a paso. "
                + "Claude mejora la interpretación si tienes ANTHROPIC_API_KEY."
        )
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white.opacity(0.55))
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        }
    }

    private func bubbleRow(_ bubble: TeamAIAssistantSession.Bubble) -> some View {
        HStack {
            if bubble.isUser { Spacer(minLength: 48) }
            Text(bubble.text)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white)
                .multilineTextAlignment(bubble.isUser ? .trailing : .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(bubble.isUser ? outgoingBlue : incomingFill)
                }
            if !bubble.isUser { Spacer(minLength: 48) }
        }
    }

    private var liveTranscriptionBubble: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 6) {
                Text("Escuchando… (toca el mic para detener)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.cyan.opacity(0.9))
                Text(session.liveTranscript.isEmpty ? "…" : session.liveTranscript)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.cyan.opacity(0.45), lineWidth: 1.2)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    }
            }
        }
    }

    private var typingRow: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.white.opacity(0.7))
            Text("Pensando…")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private var composerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let hint = session.statusHint, !hint.isEmpty {
                Text(hint)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.95))
                    .padding(.horizontal, 4)
            }

            HStack(alignment: .bottom, spacing: 10) {
                micButton

                TextField("Escribe o dicta una tarea…", text: $session.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white)
                    .lineLimit(1 ... 5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    }
                    .focused($composerFocused)

                Button {
                    session.send(
                        directory: communityVM.directory,
                        currentUserId: auth.session?.user.id,
                        inbox: inbox
                    )
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isSending
                            ? Color.white.opacity(0.28)
                            : Color(red: 0.45, green: 0.78, blue: 1.0))
                }
                .disabled(session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isSending)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                DashboardChromeCardBackground(cornerRadius: 22)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                LiquidGlassKeyboardAccessoryBar {
                    composerFocused = false
                }
            }
        }
    }

    private var micButton: some View {
        Button {
            if session.isRecordingAudio {
                session.endVoiceInput()
            } else {
                session.beginVoiceInput()
            }
        } label: {
            Image(systemName: session.isRecordingAudio ? "stop.circle.fill" : "mic.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(session.isRecordingAudio ? .red : .white)
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill(Color.white.opacity(session.isRecordingAudio ? 0.18 : 0.12))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(session.isRecordingAudio ? "Detener dictado" : "Empezar dictado")
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        let target: TeamAIScrollID?
        if session.isRecordingAudio {
            target = .live
        } else if session.isSending {
            target = .typing
        } else if let last = session.bubbles.last {
            target = .bubble(last.id)
        } else {
            target = nil
        }
        guard let target else { return }
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(target, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(target, anchor: .bottom)
            }
        }
    }
}

// MARK: - UITabBar (icono + título blancos al seleccionar; sin tinte azul del acento global)

private enum MainTabBarAppearance {
    static func applyWhiteSelection() {
        let normal = UIColor.white.withAlphaComponent(0.56)
        let selected = UIColor.white

        let item = UITabBarItemAppearance()
        item.normal.iconColor = normal
        item.normal.titleTextAttributes = [.foregroundColor: normal]
        item.selected.iconColor = selected
        item.selected.titleTextAttributes = [.foregroundColor: selected]

        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.shadowImage = UIImage()
        appearance.shadowColor = .clear

        appearance.stackedLayoutAppearance = item
        appearance.inlineLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item

        let bar = UITabBar.appearance()
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.isTranslucent = true
        bar.tintColor = selected
        bar.unselectedItemTintColor = normal
        bar.barTintColor = nil
        bar.backgroundColor = .clear
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthViewModel())
        .environmentObject(CarsViewModel())
        .environmentObject(SettingsViewModel())
}
