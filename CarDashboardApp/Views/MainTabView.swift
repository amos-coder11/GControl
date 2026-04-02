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

    /// Cierra el dictado sin añadir nada al borrador (equivalente a «cancelar»).
    func cancelVoiceInput() {
        transcriber.stopLiveTranscription()
        isRecordingAudio = false
        liveTranscript = ""
    }

    func appendCarSelection(_ car: Car) {
        let marker = "[Vehículo: \(car.coordinatorEncargoLine)]"
        if draft.contains(marker) { return }
        if draft.isEmpty {
            draft = marker
        } else {
            draft += "\n\(marker)"
        }
    }

    func appendPeerSelection(_ row: CommunityProfilesService.DirectoryRow) {
        let marker = "[Comercial: \(row.resolvedDisplayName)]"
        if draft.contains(marker) { return }
        if draft.isEmpty {
            draft = marker
        } else {
            draft += "\n\(marker)"
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
                            let preview = Self.coordinatorTaskListPreview(body: item.body, title: item.title)
                            inbox.applyTeamCoordinatorOutreach(peerUserId: row.userId, line: preview)
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

    private static func coordinatorTaskListPreview(body: String, title: String) -> String {
        let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let primary = b.isEmpty ? t : b
        if primary.count <= 76 { return primary }
        return String(primary.prefix(73)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

private enum TeamAIScrollID: Hashable {
    case typing
    case bubble(UUID)
}

struct TeamAITabView: View {
    @StateObject private var session = TeamAIAssistantSession()
    @EnvironmentObject private var communityVM: DashboardCommunityViewModel
    @EnvironmentObject private var inbox: ChatInboxStore
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var carsVM: CarsViewModel

    @State private var sendReviewConfirmed = false
    @State private var showTextDraftSheet = false

    /// Fondos de tarjetas / contraste con acentos
    private let aiBackgroundBlack = Color(red: 0.02, green: 0.04, blue: 0.09)
    /// Fondo pantalla (azul muy oscuro, más «pro IA»)
    private let vieraScreenBgTop = Color(red: 0.04, green: 0.07, blue: 0.14)
    private let vieraScreenBgBottom = Color(red: 0.02, green: 0.03, blue: 0.08)
    /// Texto de transcripción
    private let transcriptMuted = Color(red: 0.62, green: 0.68, blue: 0.78)
    /// Acentos azules Viera
    private let vieraAccent = Color(red: 0.32, green: 0.62, blue: 1)
    private let vieraAccentBright = Color(red: 0.45, green: 0.78, blue: 1)
    private let vieraIndigo = Color(red: 0.18, green: 0.28, blue: 0.52)

    private var carVoiceMatches: [Car] {
        TeamAIVoiceQuery.matchingCars(
            cars: carsVM.cars,
            liveTranscript: session.liveTranscript,
            draft: session.draft
        )
    }

    private var peerVoiceMatches: [CommunityProfilesService.DirectoryRow] {
        TeamAIVoiceQuery.matchingPeers(
            directory: communityVM.directory,
            currentUserId: auth.session?.user.id,
            liveTranscript: session.liveTranscript,
            draft: session.draft
        )
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [vieraScreenBgTop, vieraScreenBgBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    vieraAccent.opacity(0.14),
                    vieraAccentBright.opacity(0.04),
                    Color.clear,
                ],
                center: .init(x: 0.5, y: 0.22),
                startRadius: 40,
                endRadius: 280
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                buddyHeader

                if session.isRecordingAudio {
                    recordingFocusStack
                } else {
                    buddyOrbVideo(diameter: idleOrbSize)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                    buddyPromptBlock
                }

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(session.bubbles) { bubble in
                                bubbleRowDark(bubble)
                                    .id(TeamAIScrollID.bubble(bubble.id))
                            }
                            if session.isSending {
                                typingRowDark
                                    .id(TeamAIScrollID.typing)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: session.isRecordingAudio ? 100 : .infinity)
                    .onChange(of: session.bubbles.count) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: session.isSending) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                }

                if !session.isRecordingAudio {
                    voicePickersBlock
                    scheduleReviewCard
                }

                bottomControls
            }
        }
        .preferredColorScheme(.dark)
        .tint(vieraAccent)
        .sheet(isPresented: $showTextDraftSheet) {
            NavigationStack {
                TextEditor(text: $session.draft)
                    .font(.system(size: 17))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(Color(uiColor: .systemGray6))
                    .navigationTitle("Mensaje")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Listo") { showTextDraftSheet = false }
                                .fontWeight(.semibold)
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: session.draft) { _, _ in
            sendReviewConfirmed = false
        }
        .onChange(of: session.isRecordingAudio) { wasRecording, nowRecording in
            if wasRecording, !nowRecording {
                sendReviewConfirmed = false
            }
        }
    }

    private var buddyHeader: some View {
        ZStack(alignment: .top) {
            HStack {
                Spacer(minLength: 0)
                TeamVieraTopoDecoration()
                    .padding(.trailing, 6)
            }
            .padding(.top, 4)

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [vieraAccentBright, vieraAccent],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Text("Viera IA")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            vieraAccentBright.opacity(0.85),
                                            vieraAccent.opacity(0.35),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                }
                .shadow(color: vieraAccent.opacity(0.22), radius: 16, y: 6)

                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(vieraAccentBright.opacity(0.35))
                            .frame(width: 10, height: 10)
                            .blur(radius: 3)
                        Circle()
                            .fill(vieraAccentBright)
                            .frame(width: 6, height: 6)
                    }
                    Text("En línea")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.48))
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func buddyOrbVideo(diameter: CGFloat) -> some View {
        let url = Bundle.main.url(forResource: "AIBuddyFondo", withExtension: "mp4")
        ZStack {
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            vieraAccentBright.opacity(0.55),
                            vieraAccent.opacity(0.2),
                            Color.white.opacity(0.12),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                .frame(width: diameter + 6, height: diameter + 6)
                .blur(radius: 0.5)

            if url != nil {
                LoopingMutedBundledVideoView(
                    resourceName: "AIBuddyFondo",
                    videoGravity: .resizeAspectFill
                )
                .aspectRatio(1, contentMode: .fill)
                .frame(width: diameter, height: diameter)
                .clipped()
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.35),
                                    vieraAccentBright.opacity(0.25),
                                    Color.white.opacity(0.08),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                }
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                vieraIndigo.opacity(0.5),
                                aiBackgroundBlack,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: diameter, height: diameter)
                    .overlay {
                        Image(systemName: "sparkles")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(vieraAccent.opacity(0.45))
                    }
            }
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: vieraAccent.opacity(0.35), radius: 28, y: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Asistente Viera IA")
    }

    /// Texto central (solo guía; el dictado no se muestra aquí).
    private var buddyPromptBlock: some View {
        VStack(spacing: 10) {
            Text("COORDINADOR INTELIGENTE")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(
                    LinearGradient(
                        colors: [vieraAccentBright.opacity(0.9), vieraAccent.opacity(0.65)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            Text(
                "Dicta el encargo con el micrófono, elige coche y comercial en los carruseles, confirma horario y envía."
            )
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(transcriptMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    vieraAccent.opacity(0.22),
                                    Color.white.opacity(0.06),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    /// Vídeo en bucle mientras grabas (el texto dictado no se muestra en pantalla).
    private var recordingFocusStack: some View {
        VStack(spacing: 8) {
            buddyOrbVideo(diameter: recordingOrbSize)
                .padding(.top, 2)

            if !carVoiceMatches.isEmpty {
                TeamAICarVoiceCarousel(cars: carVoiceMatches) { car in
                    session.appendCarSelection(car)
                }
                .environmentObject(auth)
            }
            if !peerVoiceMatches.isEmpty {
                TeamAIPeerVoiceCarousel(
                    peers: peerVoiceMatches,
                    accessToken: auth.session?.accessToken
                ) { row in
                    session.appendPeerSelection(row)
                }
            }

            Text("Toca el micrófono de nuevo para terminar")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(vieraAccent.opacity(0.55))
                .padding(.top, 2)
        }
        .padding(.bottom, 8)
    }

    private var recordingOrbSize: CGFloat {
        min(232, UIScreen.main.bounds.width * 0.58)
    }

    private var idleOrbSize: CGFloat {
        min(220, UIScreen.main.bounds.width * 0.56)
    }

    @ViewBuilder
    private var voicePickersBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !carVoiceMatches.isEmpty {
                TeamAICarVoiceCarousel(cars: carVoiceMatches) { car in
                    session.appendCarSelection(car)
                }
                .environmentObject(auth)
            }
            if !peerVoiceMatches.isEmpty {
                TeamAIPeerVoiceCarousel(
                    peers: peerVoiceMatches,
                    accessToken: auth.session?.accessToken
                ) { row in
                    session.appendPeerSelection(row)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    private var scheduleReviewDraftTrimmed: String {
        session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var scheduleReviewCard: some View {
        if !scheduleReviewDraftTrimmed.isEmpty {
            scheduleReviewCardChrome
        }
    }

    private var scheduleReviewCardChrome: some View {
        VStack(alignment: .leading, spacing: 12) {
            scheduleReviewCardHeader
            scheduleReviewConfirmButton
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private var scheduleReviewCardHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: sendReviewConfirmed ? "checkmark.seal.fill" : "clock.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(sendReviewConfirmed ? Color.green.opacity(0.9) : Color.white.opacity(0.45))
            VStack(alignment: .leading, spacing: 4) {
                Text("Horario y revisión")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.92))
                Text(Self.localScheduleLine())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.48))
            }
            Spacer(minLength: 0)
        }
    }

    private var scheduleReviewConfirmButton: some View {
        Button {
            sendReviewConfirmed = true
        } label: {
            Text(sendReviewConfirmed ? "Revisión confirmada" : "Confirmar horario y revisión")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(sendReviewConfirmed ? Color.white.opacity(0.45) : Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background { scheduleReviewConfirmButtonFill }
        }
        .buttonStyle(.plain)
        .disabled(sendReviewConfirmed)
    }

    @ViewBuilder
    private var scheduleReviewConfirmButtonFill: some View {
        if sendReviewConfirmed {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.12))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [vieraAccent, vieraAccentBright.opacity(0.92)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }

    private static func localScheduleLine() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateStyle = .full
        f.timeStyle = .short
        return f.string(from: Date())
    }

    private func bubbleRowDark(_ bubble: TeamAIAssistantSession.Bubble) -> some View {
        HStack {
            if bubble.isUser { Spacer(minLength: 44) }
            Text(bubble.text)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.92))
                .multilineTextAlignment(bubble.isUser ? .trailing : .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(bubble.isUser ? Color.white.opacity(0.1) : vieraIndigo.opacity(0.35))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(
                                    bubble.isUser
                                        ? Color.white.opacity(0.1)
                                        : vieraAccent.opacity(0.22),
                                    lineWidth: 0.75
                                )
                        }
                }
            if !bubble.isUser { Spacer(minLength: 44) }
        }
    }

    private var typingRowDark: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(vieraAccentBright.opacity(0.85))
            Text("Viera está pensando…")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(transcriptMuted)
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private var bottomControls: some View {
        VStack(spacing: 14) {
            if let hint = session.statusHint, !hint.isEmpty {
                Text(hint)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.orange.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22)
            }
            let trimmed = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !session.isRecordingAudio {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Mensaje listo")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .tracking(0.9)
                    if !sendReviewConfirmed {
                        Text("Confirma horario y revisión antes de enviar.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.orange.opacity(0.85))
                    }
                    Text(session.draft)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        session.send(
                            directory: communityVM.directory,
                            currentUserId: auth.session?.user.id,
                            inbox: inbox
                        )
                        sendReviewConfirmed = false
                    } label: {
                        Text("Enviar al coordinador")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(
                                sendReviewConfirmed ? Color.white : Color.white.opacity(0.35)
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background {
                                if sendReviewConfirmed {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [vieraAccent, vieraAccentBright.opacity(0.9)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                } else {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.white.opacity(0.12))
                                }
                            }
                    }
                    .disabled(session.isSending || !sendReviewConfirmed)
                    .opacity(session.isSending ? 0.45 : 1)
                }
                .padding(16)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        }
                }
                .padding(.horizontal, 16)
            }
            buddyMainControlBar
        }
    }

    /// Barra inferior: teclado · micrófono · cerrar/borrar.
    private var buddyMainControlBar: some View {
        let draftTrim = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack(alignment: .center, spacing: 0) {
            Button {
                showTextDraftSheet = true
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .frame(width: 52, height: 52)
                    .background {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [vieraIndigo, vieraIndigo.opacity(0.75)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay {
                                Circle()
                                    .strokeBorder(vieraAccent.opacity(0.35), lineWidth: 1)
                            }
                    }
            }
            .buttonStyle(.plain)
            .disabled(session.isRecordingAudio)
            .opacity(session.isRecordingAudio ? 0.38 : 1)
            .accessibilityLabel("Escribir mensaje")

            Spacer(minLength: 12)

            ZStack {
                if session.isRecordingAudio {
                    ForEach(0 ..< 3, id: \.self) { ring in
                        Circle()
                            .stroke(
                                vieraAccentBright.opacity(0.28 - CGFloat(ring) * 0.06),
                                lineWidth: 1.5
                            )
                            .frame(width: 78 + CGFloat(ring) * 22, height: 78 + CGFloat(ring) * 22)
                    }
                }
                Button {
                    if session.isRecordingAudio {
                        session.endVoiceInput()
                    } else {
                        session.beginVoiceInput()
                    }
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 74, height: 74)
                        .background {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [vieraAccent, vieraAccentBright.opacity(0.95)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: vieraAccent.opacity(0.55), radius: 14, y: 6)
                        }
                }
                .buttonStyle(.plain)
            }
            .accessibilityLabel(session.isRecordingAudio ? "Terminar dictado" : "Empezar dictado")

            Spacer(minLength: 12)

            Button {
                if session.isRecordingAudio {
                    session.cancelVoiceInput()
                } else if !draftTrim.isEmpty {
                    session.draft = ""
                    sendReviewConfirmed = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 52, height: 52)
                    .background {
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                            }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.isRecordingAudio ? "Cancelar dictado" : "Borrar borrador")
            .disabled(!session.isRecordingAudio && draftTrim.isEmpty)
            .opacity(session.isRecordingAudio || !draftTrim.isEmpty ? 1 : 0.4)
        }
        .padding(.horizontal, 26)
        .padding(.top, 6)
        .padding(.bottom, 22)
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        let target: TeamAIScrollID?
        if session.isSending {
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

// MARK: - Decoración cabecera Viera (líneas tipo topográficas)

private struct TeamVieraTopoDecoration: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let stroke = Color(red: 0.45, green: 0.72, blue: 1).opacity(0.22)
            for i in 0 ..< 7 {
                let o = CGFloat(i) * 5
                var p = Path()
                p.move(to: CGPoint(x: w * 0.05 + o * 0.3, y: h * 0.15))
                p.addQuadCurve(
                    to: CGPoint(x: w * 0.92 - o * 0.2, y: h * 0.88 - o * 0.15),
                    control: CGPoint(x: w * 0.55 + o * 0.15, y: h * 0.35 - o * 0.1)
                )
                context.stroke(p, with: .color(stroke), lineWidth: 1)
            }
            for i in 0 ..< 5 {
                let o = CGFloat(i) * 6 + 3
                var p2 = Path()
                p2.move(to: CGPoint(x: w * 0.35, y: o))
                p2.addQuadCurve(
                    to: CGPoint(x: w - o * 0.2, y: h * 0.5),
                    control: CGPoint(x: w * 0.7, y: h * 0.22 + o * 0.08)
                )
                context.stroke(p2, with: .color(stroke.opacity(0.75)), lineWidth: 0.75)
            }
        }
        .frame(width: 96, height: 76)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Coordinador IA · voz + carruseles (aquí para garantizar compilación en el target)

extension Car {
    fileprivate var coordinatorVoiceHaystack: String {
        [
            name, model, plate, String(year),
            brandName ?? "", fuelType ?? "", bodyType ?? "", locationText ?? "",
            dgtLabel ?? "", transmission ?? "", equipmentSummary ?? "", exteriorColorLabel ?? "",
            color,
        ]
            .joined(separator: " ")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
            .lowercased()
    }

    var coordinatorEncargoLine: String {
        let b = (brandName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let headline = [b, name].filter { !$0.isEmpty }.joined(separator: " ")
        let p = plate.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(headline) · mat. \(p) · \(year)"
    }

    var coordinatorVoiceTitleLine: String {
        let b = (brandName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let headline = [b, model].filter { !$0.isEmpty }.joined(separator: " ")
        return headline.isEmpty ? name : headline
    }

    func matchesAnyCoordinatorToken(_ tokens: [String]) -> Bool {
        guard !tokens.isEmpty else { return false }
        let hay = coordinatorVoiceHaystack
        return tokens.contains { tok in hay.contains(tok) }
    }
}

enum TeamAIVoiceQuery {
    private static let stopwords: Set<String> = [
        "el", "la", "los", "las", "un", "una", "unos", "unas", "lo", "le", "les",
        "que", "de", "y", "a", "en", "por", "para", "con", "sin", "sobre", "al", "del",
        "me", "te", "se", "nos", "os", "yo", "tú", "tu", "su", "sus", "mi", "mis",
        "esto", "esta", "ese", "esa", "eso", "aquí", "allí", "muy", "más", "menos",
        "solo", "sólo", "digo", "quiero", "mande", "manda", "mandar", "dile", "decir",
        "coordinador", "coordinadora", "hola", "buenos", "días", "tardes", "porfa", "favor",
        "vale", "bueno", "pues", "entonces", "así", "como", "cuando", "donde", "hay", "ser",
        "tengo", "tiene", "tienen", "mensaje", "avisar", "avisame",
        "stock", "coche", "coches", "auto", "vehículo", "vehiculo", "anuncio",
    ]

    static func meaningfulTokens(from text: String) -> [String] {
        let folded = text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES")).lowercased()
        let parts = folded.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { tok in
                if tok.count < 2 { return false }
                if stopwords.contains(tok) { return false }
                return true
            }
    }

    static func matchingCars(cars: [Car], liveTranscript: String, draft: String, limit: Int = 16) -> [Car] {
        let blob = "\(liveTranscript) \(draft)"
        let tokens = meaningfulTokens(from: blob)
        guard !tokens.isEmpty else { return [] }
        let hit = cars.filter { $0.matchesAnyCoordinatorToken(tokens) }
        return Array(hit.prefix(limit))
    }

    static func matchingPeers(
        directory: [CommunityProfilesService.DirectoryRow],
        currentUserId: UUID?,
        liveTranscript: String,
        draft: String,
        limit: Int = 12
    ) -> [CommunityProfilesService.DirectoryRow] {
        let peers = directory
            .filter { $0.userId != currentUserId }
            .sorted {
                $0.resolvedDisplayName.localizedCaseInsensitiveCompare($1.resolvedDisplayName) == .orderedAscending
            }
        let blob = "\(liveTranscript) \(draft)"
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
            .lowercased()
        let tokens = meaningfulTokens(from: blob)
        let teamKeywords = ["comercial", "comerciales", "vendedor", "vendedora", "equipo", "compañero", "compañera", "compañeros", "persona", "contacto"]
        let keywordHit = teamKeywords.contains { blob.contains($0) }
        if keywordHit, tokens.isEmpty {
            return Array(peers.prefix(limit))
        }
        guard !tokens.isEmpty else { return [] }
        let matched = peers.filter { row in
            let name = row.resolvedDisplayName
                .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
                .lowercased()
            return tokens.contains { name.contains($0) }
        }
        return Array(matched.prefix(limit))
    }
}

struct TeamAICarVoiceCarousel: View {
    @EnvironmentObject private var auth: AuthViewModel
    let cars: [Car]
    var onSelect: (Car) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
                Text("Stock · toca un anuncio")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Color.white.opacity(0.42))
            }
            .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(cars) { car in
                        Button {
                            onSelect(car)
                        } label: {
                            VStack(spacing: 8) {
                                CarThumbnailView(car: car, size: 58)
                                Text(car.coordinatorVoiceTitleLine)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.white.opacity(0.88))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .frame(width: 104)
                                Text(car.plate)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.38))
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 10)
                            .background {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(0.07))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                                    }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
    }
}

struct TeamAIPeerVoiceCarousel: View {
    let peers: [CommunityProfilesService.DirectoryRow]
    var accessToken: String?
    var onSelect: (CommunityProfilesService.DirectoryRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
                Text("Equipo · toca un comercial")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Color.white.opacity(0.42))
            }
            .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(peers, id: \.id) { row in
                        Button {
                            onSelect(row)
                        } label: {
                            VStack(spacing: 8) {
                                TeamDirectoryProfileAvatar(
                                    row: row,
                                    accessToken: accessToken,
                                    diameter: 60,
                                    localAvatarImage: nil,
                                    localInitialsOverride: nil
                                )
                                .overlay {
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1.2)
                                }
                                Text(row.resolvedDisplayName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.white.opacity(0.9))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .frame(width: 96)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 8)
                            .background {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(0.07))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                                    }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
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
