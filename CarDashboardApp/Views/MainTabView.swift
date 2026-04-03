import AVFoundation
import Combine
import Speech
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
                    .toolbar(.hidden, for: .tabBar)
                    .toolbarBackground(.hidden, for: .tabBar)
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
        .onReceive(NotificationCenter.default.publisher(for: .coordinatorTaskAcceptedFromPush)) { _ in
            guard let uid = auth.session?.user.id else { return }
            Task {
                await chatInbox.refreshCoordinatorTasksFromServer(currentUserId: uid)
            }
        }
    }
}

// MARK: - Pestaña IA (mismo archivo que MainTabView para evitar «Cannot find TeamAITabView in scope» si falta el .swift en el target)

/// Borrador del compositor aislado: al teclear no se invalida el `ScrollView` de burbujas (menos jank con teclado).
@MainActor
private final class TeamAIComposerState: ObservableObject {
    @Published var draft: String = ""
}

@MainActor
private final class TeamAIAssistantSession: ObservableObject {
    struct Bubble: Identifiable, Equatable {
        let id: UUID
        let isUser: Bool
        let text: String
        /// Tarjetas visuales (equipo / coches) parseadas del bloque `<<<VIERA_CARDS>>>`.
        var cardPayload: VieraCardPayload?

        init(id: UUID = UUID(), isUser: Bool, text: String, cardPayload: VieraCardPayload? = nil) {
            self.id = id
            self.isUser = isUser
            self.text = text
            self.cardPayload = cardPayload
        }
    }

    /// Listado equipo + inventario para el system prompt (desde `TeamAITabView`).
    var vieraAppContextBuilder: (() -> String)?

    @Published var bubbles: [Bubble] = []
    /// Asignado desde la vista (`attachComposer`); el texto del campo «Mensaje» vive en `TeamAIComposerState`.
    private weak var composerRef: TeamAIComposerState?

    @Published var liveTranscript: String = ""
    @Published var isRecordingAudio = false
    /// Grabación tipo «nota de voz» (mantener pulsado); al soltar se transcribe y se envía.
    @Published var isRecordingVoiceNote = false
    @Published var isSending = false
    /// Texto parcial mientras llega el stream de OpenAI (efecto «typewriter»).
    @Published var streamingAssistantText: String = ""
    @Published var statusHint: String?

    private let transcriber: LiveSpeechTranscriber
    fileprivate let waveformMonitor = AudioWaveformMonitor()
    private var cancellables = Set<AnyCancellable>()
    private var voiceNoteRecorder: AVAudioRecorder?
    private var voiceNoteURL: URL?

    init() {
        transcriber = LiveSpeechTranscriber(waveformMonitor: waveformMonitor)
        transcriber.$partialText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.liveTranscript = text
            }
            .store(in: &cancellables)
    }

    func attachComposer(_ composer: TeamAIComposerState) {
        composerRef = composer
    }

    func beginVoiceInput() {
        guard !isRecordingAudio, !isRecordingVoiceNote else { return }
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
                    self.waveformMonitor.beginExternalAudioFeed()
                    try self.transcriber.startLiveTranscription()
                } catch {
                    self.waveformMonitor.endExternalAudioFeed()
                    self.isRecordingAudio = false
                    self.statusHint = error.localizedDescription
                }
            }
        }
    }

    func endVoiceInput() {
        let captured = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        transcriber.stopLiveTranscription()
        waveformMonitor.endExternalAudioFeed()
        isRecordingAudio = false
        liveTranscript = ""
        mergeCapturedTranscriptIntoDraft(captured)
    }

    /// Termina el dictado y envía el mensaje (flecha durante grabación, estilo ChatGPT).
    func endVoiceInputAndSend() {
        let captured = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        transcriber.stopLiveTranscription()
        waveformMonitor.endExternalAudioFeed()
        isRecordingAudio = false
        liveTranscript = ""
        mergeCapturedTranscriptIntoDraft(captured)
        send()
    }

    private func mergeCapturedTranscriptIntoDraft(_ captured: String) {
        guard let c = composerRef, !captured.isEmpty else { return }
        if c.draft.isEmpty {
            c.draft = captured
        } else if c.draft.hasSuffix(" ") {
            c.draft += captured
        } else {
            c.draft += " " + captured
        }
    }

    /// Cierra el dictado sin añadir nada al borrador (equivalente a «cancelar»).
    func cancelVoiceInput() {
        transcriber.stopLiveTranscription()
        waveformMonitor.endExternalAudioFeed()
        isRecordingAudio = false
        liveTranscript = ""
    }

    // MARK: - Nota de voz (mantener pulsado en el mic / onda)

    func startVoiceNoteRecording() async {
        guard !isRecordingAudio, !isRecordingVoiceNote else { return }
        statusHint = nil
        let mic = await requestMicrophonePermission()
        guard mic else {
            statusHint = "Activa el micrófono en Ajustes para enviar notas de voz."
            return
        }
        let speech = await transcriber.requestSpeechAuthorization()
        guard speech else {
            statusHint = "Activa el reconocimiento de voz en Ajustes."
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("viera-vn-\(UUID().uuidString).m4a")
        voiceNoteURL = url
        do {
            let av = AVAudioSession.sharedInstance()
            try av.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
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
                throw NSError(domain: "CarHub", code: 1, userInfo: [NSLocalizedDescriptionKey: "No se pudo grabar audio."])
            }
            voiceNoteRecorder = rec
            isRecordingVoiceNote = true
        } catch {
            voiceNoteURL = nil
            voiceNoteRecorder = nil
            statusHint = error.localizedDescription
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func cancelVoiceNoteRecording() {
        voiceNoteRecorder?.stop()
        voiceNoteRecorder = nil
        if let url = voiceNoteURL {
            try? FileManager.default.removeItem(at: url)
        }
        voiceNoteURL = nil
        isRecordingVoiceNote = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Detiene la grabación, transcribe el archivo y envía el texto a Viera (mensaje de voz → texto).
    func finishVoiceNoteRecordingAndSend() async {
        guard isRecordingVoiceNote else { return }
        voiceNoteRecorder?.stop()
        voiceNoteRecorder = nil
        isRecordingVoiceNote = false

        guard let url = voiceNoteURL else {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        voiceNoteURL = nil
        defer {
            try? FileManager.default.removeItem(at: url)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-ES")), recognizer.isAvailable else {
            statusHint = "El reconocimiento de voz no está disponible ahora."
            return
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let lock = NSLock()
            var finished = false
            func finishOnce() {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                cont.resume()
            }
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    DispatchQueue.main.async {
                        self.statusHint = error.localizedDescription
                        finishOnce()
                    }
                    return
                }
                guard let result else {
                    DispatchQueue.main.async { finishOnce() }
                    return
                }
                if result.isFinal {
                    let text = result.bestTranscription.formattedString
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    DispatchQueue.main.async {
                        if text.isEmpty {
                            self.statusHint = "No se ha entendido el audio. Mantén pulsado y vuelve a intentarlo."
                        } else if let c = self.composerRef {
                            c.draft = text
                            self.send()
                        }
                        finishOnce()
                    }
                }
            }
        }
    }

    func send() {
        guard let c = composerRef else { return }
        let text = c.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        c.draft = ""
        bubbles.append(Bubble(isUser: true, text: text))
        isSending = true
        statusHint = nil

        let conversation = bubbles.map { ($0.isUser, $0.text) }

        let dataSupplement = vieraAppContextBuilder?() ?? ""

        Task { @MainActor [self] in
            do {
                if OpenAIChatClient.isConfigured {
                    self.streamingAssistantText = ""
                    let supplement = dataSupplement.trimmingCharacters(in: .whitespacesAndNewlines)
                    try await OpenAIChatClient.streamVieraChatReply(
                        conversation: conversation,
                        dataContextSupplement: supplement.isEmpty ? nil : supplement
                    ) { chunk in
                        await MainActor.run { [self] in
                            self.streamingAssistantText += chunk
                        }
                    }
                    let split = VieraCardsParser.split(raw: self.streamingAssistantText)
                    self.streamingAssistantText = ""
                    let final = split.visible.trimmingCharacters(in: .whitespacesAndNewlines)
                    if final.isEmpty {
                        self.statusHint = "La respuesta ha llegado vacía. Inténtalo de nuevo."
                    } else {
                        self.bubbles.append(Bubble(isUser: false, text: final, cardPayload: split.payload))
                    }
                    self.isSending = false
                } else {
                    let reply = Self.offlineAssistantHint
                    self.bubbles.append(Bubble(isUser: false, text: reply))
                    self.isSending = false
                }
            } catch {
                self.streamingAssistantText = ""
                self.statusHint = error.localizedDescription
                self.isSending = false
            }
        }
    }

    private static let offlineAssistantHint = """
    Para que Viera responda aquí, crea el archivo DeveloperSettings.local.xcconfig en la carpeta CarDashboardApp \
    (copia el .example y renómbralo; no uses solo el .example) y añade:
    OPENAI_API_KEY = sk-proj-tu_clave
    Limpia el proyecto (Product → Clean Build Folder) y vuelve a compilar.
    """

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { ok in
                cont.resume(returning: ok)
            }
        }
    }

}

private enum TeamAIScrollID: Hashable {
    case typing
    case streaming
    case bubble(UUID)
}

/// Editor a pantalla grande para mensajes muy largos (scroll interno, estilo ChatGPT).
private struct TeamAILongMessageDraftSheet: View {
    @Binding var text: String
    var isSending: Bool
    var onDismiss: () -> Void
    var onSend: () -> Void

    @FocusState private var editorFocused: Bool

    private let sheetBg = Color(red: 0.09, green: 0.09, blue: 0.1)

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !trimmed.isEmpty && !isSending
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                sheetBg.ignoresSafeArea()
                TextEditor(text: $text)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .tint(Color(red: 0, green: 0.48, blue: 1))
                    .scrollContentBackground(.hidden)
                    .padding(.leading, 14)
                    .padding(.trailing, 40)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .focused($editorFocused)
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.48))
                        .padding(10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cerrar editor")
                .padding(.trailing, 4)
                .padding(.top, 4)
            }
            .navigationTitle("Mensaje")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(sheetBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
                Button {
                    onSend()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(canSend ? Color.black : Color.black.opacity(0.38))
                        .frame(width: 48, height: 48)
                        .background {
                            Circle()
                                .fill(canSend ? Color.white : Color.white.opacity(0.38))
                                .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 6)
                                .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Enviar mensaje")
                .padding(.trailing, 14)
                .padding(.bottom, 6)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                editorFocused = true
            }
        }
    }
}

/// Cursor parpadeante al final del texto en streaming (estilo chat IA).
private struct StreamingTextCaret: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.45, paused: false)) { ctx in
            let pulse = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) < 0.45
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color(red: 0.45, green: 0.78, blue: 1).opacity(0.95))
                .frame(width: 2, height: 15)
                .opacity(pulse ? 1 : 0.22)
        }
    }
}

/// Toca = dictado en vivo; mantén ~0,45 s = nota de voz → al soltar se transcribe y se envía a Viera.
private struct VieraTapOrHoldVoiceControl: View {
    @ObservedObject var session: TeamAIAssistantSession
    var systemName: String
    var pointSize: CGFloat
    var fontWeight: Font.Weight = .medium
    var hitSide: CGFloat = 44
    var foreground: Color
    var accessibilityLabelText: String

    @State private var pressToken = 0
    @State private var fingerDown = false

    private let holdNanoseconds: UInt64 = 450_000_000

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: pointSize, weight: fontWeight))
            .foregroundStyle(foreground)
            .frame(width: hitSide, height: hitSide)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !session.isRecordingAudio else { return }
                        if !fingerDown {
                            fingerDown = true
                            pressToken &+= 1
                            let token = pressToken
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: holdNanoseconds)
                                guard !Task.isCancelled, token == pressToken, fingerDown else { return }
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                await session.startVoiceNoteRecording()
                            }
                        }
                    }
                    .onEnded { _ in
                        guard !session.isRecordingAudio else {
                            fingerDown = false
                            return
                        }
                        pressToken &+= 1
                        let wasVoiceNote = session.isRecordingVoiceNote
                        fingerDown = false
                        if wasVoiceNote {
                            Task { await session.finishVoiceNoteRecordingAndSend() }
                        } else {
                            session.beginVoiceInput()
                        }
                    }
            )
            .accessibilityLabel(accessibilityLabelText)
            .accessibilityHint("Mantén pulsado para grabar una nota de voz y enviarla. Toca para dictado en vivo.")
    }
}

/// Compositor inferior aislado: al editar «Mensaje…» no se recompone el `ScrollView` de burbujas (teclado más fluido).
private struct TeamAIComposerDockView: View {
    @ObservedObject var session: TeamAIAssistantSession
    @ObservedObject var composerState: TeamAIComposerState
    @Binding var showPlusMenuSheet: Bool
    @Binding var showTextDraftSheet: Bool

    @FocusState private var composerFieldFocused: Bool

    private let composerInlineLineRange = 1...8
    private let teamAIComposerWaveformStripHeight: CGFloat = 26
    private let teamAIComposerRowMinHeight: CGFloat = 44

    private func shouldShowComposerExpandButton(draft: String, isRecording: Bool) -> Bool {
        guard !isRecording, !draft.isEmpty else { return false }
        let newlines = draft.reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
        return draft.count >= 100 || newlines >= 2
    }

    private func submitComposerMessageIfPossible() {
        let text = composerState.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !session.isSending else { return }
        session.send()
        composerFieldFocused = false
    }

    var body: some View {
        VStack(spacing: 12) {
            if let hint = session.statusHint, !hint.isEmpty {
                Text(hint)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.orange.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22)
            }

            if session.isRecordingVoiceNote {
                Text("Suelta para transcribir y enviar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.cyan.opacity(0.85))
                    .multilineTextAlignment(.center)
            }

            unifiedComposerBar
        }
        .padding(.bottom, 10)
    }

    private var unifiedComposerBar: some View {
        let trimmed = composerState.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLive = session.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasText = !trimmed.isEmpty
        let canSendIdle = hasText && !session.isSending
        let recording = session.isRecordingAudio
        let canSendWhileRecording = !session.isSending && (hasText || !trimmedLive.isEmpty)
        let showExpand = shouldShowComposerExpandButton(draft: composerState.draft, isRecording: recording)

        return HStack(alignment: .bottom, spacing: 10) {
            if recording {
                Button {
                    session.endVoiceInput()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 44, height: 44)
                        .background {
                            TeamAIGlassCircleBackground()
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pausar dictado")
            } else {
                Button {
                    showPlusMenuSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .frame(width: 44, height: 44)
                        .background {
                            TeamAIGlassCircleBackground()
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Más opciones")
            }

            HStack(alignment: .bottom, spacing: 4) {
                ZStack(alignment: .topLeading) {
                    TextField(
                        "",
                        text: $composerState.draft,
                        prompt: Text("Mensaje…")
                            .foregroundStyle(Color.white.opacity(0.42)),
                        axis: .vertical
                    )
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.white)
                    .tint(Color(red: 0, green: 0.48, blue: 1))
                    .lineLimit(composerInlineLineRange)
                    .textFieldStyle(.plain)
                    .focused($composerFieldFocused)
                    .submitLabel(.send)
                    .onSubmit { submitComposerMessageIfPossible() }
                    .opacity(recording ? 0.02 : 1)
                    .padding(.trailing, showExpand && !recording ? 26 : 0)

                    if recording {
                        AudioWaveformView(
                            monitor: session.waveformMonitor,
                            barColor: Color.white.opacity(0.88),
                            barWidth: 1,
                            spacing: 1,
                            layoutHeight: teamAIComposerWaveformStripHeight,
                            fillsAvailableWidth: true
                        )
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: teamAIComposerWaveformStripHeight, maxHeight: teamAIComposerWaveformStripHeight)
                        .mask {
                            LinearGradient(
                                stops: [
                                    .init(color: .black.opacity(0.12), location: 0),
                                    .init(color: .black, location: 0.12),
                                    .init(color: .black, location: 0.88),
                                    .init(color: .black.opacity(0.12), location: 1)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        }
                        .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if showExpand && !recording {
                        Button {
                            showTextDraftSheet = true
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.5))
                                .padding(6)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Ampliar mensaje")
                        .padding(.top, 2)
                        .padding(.trailing, 2)
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 8)
                .padding(.vertical, 10)
                .frame(minHeight: teamAIComposerRowMinHeight, alignment: .center)

                if !recording && !hasText {
                    VieraTapOrHoldVoiceControl(
                        session: session,
                        systemName: "mic.fill",
                        pointSize: 17,
                        foreground: session.isRecordingVoiceNote
                            ? Color.red.opacity(0.92)
                            : Color.white.opacity(0.88),
                        accessibilityLabelText: "Micrófono"
                    )
                }
            }
            .background {
                TeamAIGlassComposerFieldBackground()
            }

            if recording {
                Button {
                    session.endVoiceInputAndSend()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(canSendWhileRecording ? Color.black : Color.black.opacity(0.38))
                        .frame(width: 48, height: 48)
                        .background {
                            Circle()
                                .fill(canSendWhileRecording ? Color.white : Color.white.opacity(0.38))
                                .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 6)
                                .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(!canSendWhileRecording)
                .accessibilityLabel("Enviar mensaje")
            } else if hasText {
                Button {
                    submitComposerMessageIfPossible()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(canSendIdle ? Color.black : Color.black.opacity(0.38))
                        .frame(width: 48, height: 48)
                        .background {
                            Circle()
                                .fill(canSendIdle ? Color.white : Color.white.opacity(0.38))
                                .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 6)
                                .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(session.isSending)
                .accessibilityLabel("Enviar mensaje")
            } else {
                ZStack {
                    Circle()
                        .fill(session.isRecordingVoiceNote ? Color.red.opacity(0.35) : Color.white)
                        .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 6)
                        .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
                        .frame(width: 48, height: 48)
                    VieraTapOrHoldVoiceControl(
                        session: session,
                        systemName: "waveform",
                        pointSize: 20,
                        fontWeight: .semibold,
                        hitSide: 48,
                        foreground: session.isRecordingVoiceNote ? Color.white : Color.black,
                        accessibilityLabelText: "Voz"
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }
}

struct TeamAITabView: View {
    @StateObject private var session = TeamAIAssistantSession()
    @StateObject private var composerState = TeamAIComposerState()
    @EnvironmentObject private var tabRouter: MainTabRouter
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var carsVM: CarsViewModel
    @EnvironmentObject private var communityVM: DashboardCommunityViewModel
    @EnvironmentObject private var chatInbox: ChatInboxStore
    @EnvironmentObject private var chatNav: ChatNavigationCoordinator

    @State private var showTextDraftSheet = false
    @State private var showPlusMenuSheet = false

    @State private var speechSynth = AVSpeechSynthesizer()
    /// 0 ninguno, 1 pulgar arriba, -1 pulgar abajo (por id de burbuja del asistente).
    @State private var assistantThumbByBubbleId: [UUID: Int] = [:]

    /// Fondo solo del listado de mensajes (cabecera y compositor: sin capa negra, solo controles con cristal).
    private let cgptBlack = Color(red: 0, green: 0, blue: 0)

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

    /// Espacio vacío bajo el hilo (estilo ChatGPT). Valores muy altos + teclado fuerzan relayout costoso.
    private var chatScrollBottomBreathingRoom: CGFloat {
        max(220, UIScreen.main.bounds.height * 0.36)
    }

    @State private var streamScrollDebounceTask: Task<Void, Never>?

    private func isVeryLongUserMessage(_ text: String) -> Bool {
        let n = text.count
        let newlines = text.reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
        return n >= 360 || newlines >= 10
    }

    private var assistantToolbarIconFont: Font {
        .system(size: 13, weight: .light)
    }

    var body: some View {
        VStack(spacing: 0) {
            chatGPTTopChrome
            memoryStatusRow

            if session.isRecordingAudio {
                recordingFocusStack
            }

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(session.bubbles.enumerated()), id: \.element.id) { idx, bubble in
                            bubbleRowDark(bubble, index: idx)
                                .id(TeamAIScrollID.bubble(bubble.id))
                        }
                        if session.isSending {
                            if session.streamingAssistantText.isEmpty {
                                typingRowDark
                                    .id(TeamAIScrollID.typing)
                            } else {
                                streamingAssistantBubbleRow(session.streamingAssistantText)
                                    .id(TeamAIScrollID.streaming)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .padding(.bottom, chatScrollBottomBreathingRoom)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollContentBackground(.hidden)
                .background(cgptBlack)
                .scrollDismissesKeyboard(.automatic)
                .onChange(of: session.bubbles.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: session.isSending) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: session.streamingAssistantText) { _, _ in
                    scheduleDebouncedStreamScroll(proxy: proxy)
                }
            }

            TeamAIComposerDockView(
                session: session,
                composerState: composerState,
                showPlusMenuSheet: $showPlusMenuSheet,
                showTextDraftSheet: $showTextDraftSheet
            )
        }
        .background(Color.clear)
        .preferredColorScheme(.dark)
        .tint(.white)
        .onDisappear {
            streamScrollDebounceTask?.cancel()
            streamScrollDebounceTask = nil
        }
        .onAppear {
            session.attachComposer(composerState)
            session.vieraAppContextBuilder = { [communityVM, carsVM, auth] in
                VieraChatContextBuilder.build(
                    directory: communityVM.directory,
                    cars: carsVM.cars,
                    currentUserId: auth.session?.user.id
                )
            }
        }
        .sheet(isPresented: $showPlusMenuSheet) {
            TeamAIPlusMenuSheet(
                onDismiss: { showPlusMenuSheet = false },
                onWriteMessage: {
                    showPlusMenuSheet = false
                    showTextDraftSheet = true
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTextDraftSheet) {
            TeamAILongMessageDraftSheet(
                text: $composerState.draft,
                isSending: session.isSending,
                onDismiss: { showTextDraftSheet = false },
                onSend: {
                    let t = composerState.draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty, !session.isSending else { return }
                    session.send()
                    showTextDraftSheet = false
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var chatGPTTopChrome: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Inicio") { tabRouter.selected = .home }
                Button("Coches") { tabRouter.selected = .cars }
                Button("Chat") { tabRouter.selected = .chat }
                Button("Ajustes") { tabRouter.selected = .settings }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .background {
                        TeamAIGlassCircleBackground()
                    }
            }

            Spacer(minLength: 0)

            Menu {
                Section("Modelo") {
                    Text("Viera IA — asistente CarHub")
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Viera IA")
                        .font(.system(size: 16, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background {
                    TeamAIGlassCapsuleBackground()
                }
            }

            Spacer(minLength: 0)

            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var memoryStatusRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.blue.opacity(0.85))
            Text("Memoria desactivada")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.5))
            Image(systemName: "info.circle")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 10)
    }

    /// Borde izquierdo: deslizar hacia la derecha (como «atrás» en un chat) → Inicio.
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
                    videoGravity: AVLayerVideoGravity.resizeAspectFill
                )
                .aspectRatio(1, contentMode: ContentMode.fill)
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

    /// Vídeo en bucle mientras grabas (el texto dictado no se muestra en pantalla).
    private var recordingFocusStack: some View {
        VStack(spacing: 8) {
            buddyOrbVideo(diameter: recordingOrbSize)
                .padding(.top, 2)

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

    private var chatBubbleMaxUserWidth: CGFloat {
        min(320, UIScreen.main.bounds.width - 72)
    }

    /// Respuesta en vivo: texto visible (sin bloque JSON); tarjetas cuando el cierre `>>>` ya llegó en el stream.
    private var lastUserMessageForVieraContext: String? {
        session.bubbles.last(where: { $0.isUser })?.text
    }

    private func lastUserTextBeforeBubble(at index: Int) -> String? {
        guard index > 0 else { return nil }
        var j = index - 1
        while j >= 0 {
            let b = session.bubbles[j]
            if b.isUser { return b.text }
            j -= 1
        }
        return nil
    }

    /// Mientras llega el stream solo texto; coches/equipo aparecen al terminar el mensaje (burbuja final).
    private func streamingAssistantBubbleRow(_ raw: String) -> some View {
        let visible = VieraCardsParser.visibleText(from: raw)
        return HStack(alignment: .bottom, spacing: 4) {
            Text(visible)
                .font(.system(size: 16, weight: .regular, design: .default))
                .foregroundStyle(Color.white.opacity(0.95))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.interpolate)
            StreamingTextCaret()
                .padding(.bottom, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bubbleRowDark(_ bubble: TeamAIAssistantSession.Bubble, index: Int) -> some View {
        Group {
            if bubble.isUser {
                HStack(alignment: .bottom, spacing: 0) {
                    Spacer(minLength: 8)
                    let bubbleHPadding: CGFloat = 14
                    let textMax = max(0, chatBubbleMaxUserWidth - bubbleHPadding * 2)
                    Text(bubble.text)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: textMax, alignment: .trailing)
                        .padding(.horizontal, bubbleHPadding)
                        .padding(.vertical, 10)
                        .background {
                            TeamAIGlassRoundedCardBackground(cornerRadius: 18)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(bubble.text)
                        .font(.system(size: 16, weight: .regular, design: .default))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentTransition(.interpolate)

                    let cardPayload = bubble.cardPayload ?? VieraCardPayload(team: nil, cars: nil)
                    VieraAssistantRichCardsView(
                        payload: cardPayload,
                        directory: communityVM.directory,
                        cars: carsVM.cars,
                        mentionSourceText: bubble.text,
                        mentionExtraUserText: lastUserTextBeforeBubble(at: index)
                    )
                    .environmentObject(auth)
                    .environmentObject(chatInbox)
                    .environmentObject(tabRouter)
                    .environmentObject(chatNav)
                    .environmentObject(communityVM)
                    .padding(.top, 16)

                    assistantMessageToolbar(bubbleId: bubble.id, text: bubble.text)
                        .padding(.top, 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Iconos bajo el mensaje del asistente (referencia tipo ChatGPT: trazo fino, compactos).
    private func assistantMessageToolbar(bubbleId: UUID, text: String) -> some View {
        let thumb = assistantThumbByBubbleId[bubbleId] ?? 0
        return HStack(spacing: 14) {
            Button {
                UIPasteboard.general.string = text
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(assistantToolbarIconFont)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copiar")

            Button {
                speechSynth.stopSpeaking(at: .immediate)
                let u = AVSpeechUtterance(string: text)
                u.voice = AVSpeechSynthesisVoice(language: "es-ES")
                u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
                speechSynth.speak(u)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "speaker.wave.2")
                    .font(assistantToolbarIconFont)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Leer en voz alta")

            Button {
                assistantThumbByBubbleId[bubbleId] = thumb == 1 ? 0 : 1
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: thumb == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(assistantToolbarIconFont)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Me gusta")

            Button {
                assistantThumbByBubbleId[bubbleId] = thumb == -1 ? 0 : -1
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: thumb == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .font(assistantToolbarIconFont)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("No me gusta")

            ShareLink(item: text, preview: SharePreview("Viera", icon: Image(systemName: "sparkles"))) {
                Image(systemName: "square.and.arrow.up")
                    .font(assistantToolbarIconFont)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Compartir")

            Menu {
                Button("Copiar mensaje") {
                    UIPasteboard.general.string = text
                }
                Divider()
                Button("Detener lectura", role: .none) {
                    speechSynth.stopSpeaking(at: .immediate)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(assistantToolbarIconFont)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Más opciones")
        }
        .foregroundStyle(Color.white.opacity(0.62))
    }

    private var typingRowDark: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(vieraAccentBright.opacity(0.85))
            Text("Viera está pensando…")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(transcriptMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scheduleDebouncedStreamScroll(proxy: ScrollViewProxy) {
        streamScrollDebounceTask?.cancel()
        streamScrollDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            scrollToBottom(proxy: proxy, animated: false)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        let target: TeamAIScrollID?
        var anchor: UnitPoint = .bottom

        if session.isSending {
            if session.streamingAssistantText.isEmpty {
                if let last = session.bubbles.last, last.isUser, isVeryLongUserMessage(last.text) {
                    target = .bubble(last.id)
                    anchor = .top
                } else {
                    target = .typing
                }
            } else {
                target = .streaming
            }
        } else if let last = session.bubbles.last {
            target = .bubble(last.id)
            if last.isUser, isVeryLongUserMessage(last.text) {
                anchor = .top
            }
        } else {
            target = nil
        }

        guard let target else { return }
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(target, anchor: anchor)
                }
            } else {
                proxy.scrollTo(target, anchor: anchor)
            }
        }
    }
}

// MARK: - Chrome estilo chat (glass, tarjetas, ondas, menú +)

/// Cristal oscuro sobre negro: material + velo y bisel tipo liquid glass.
private struct TeamAIGlassCapsuleBackground: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.14),
                                Color.white.opacity(0.05),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.42),
                                Color.white.opacity(0.14),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.45), radius: 22, x: 0, y: 12)
            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
    }
}

/// Campo de mensaje multilínea: esquinas **fijas** (no `Capsule`), para que al crecer en altura
/// no queden semicírculos arriba/abajo que comen el texto (comportamiento tipo iMessage / ChatGPT).
private struct TeamAIGlassComposerFieldBackground: View {
    var cornerRadius: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.14),
                                Color.white.opacity(0.05),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.42),
                                Color.white.opacity(0.14),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.45), radius: 22, x: 0, y: 12)
            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
    }
}

private struct TeamAIGlassCircleBackground: View {
    var body: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .background {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.38),
                                Color.white.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)
            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
    }
}

private struct TeamAIGlassRoundedCardBackground: View {
    var cornerRadius: CGFloat = 18

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.1),
                                Color.white.opacity(0.03)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.4), radius: 18, x: 0, y: 10)
    }
}

private struct TeamAIPlusMenuSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onDismiss: () -> Void
    var onWriteMessage: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 14) {
                        plusQuickButton(icon: "camera.fill", title: "Cámara")
                        plusQuickButton(icon: "photo.on.rectangle", title: "Fotos")
                        plusQuickButton(icon: "paperclip", title: "Archivos")
                    }
                    .padding(.top, 4)

                    plusFeatureRow(
                        icon: "paintbrush.pointed",
                        title: "Crea una imagen",
                        subtitle: "Próximamente en CarHub"
                    )
                    plusFeatureRow(
                        icon: "text.bubble",
                        title: "Escribir mensaje",
                        subtitle: "Editor para textos largos"
                    ) {
                        onWriteMessage()
                    }
                    plusFeatureRow(
                        icon: "globe",
                        title: "Búsqueda en Internet",
                        subtitle: "No disponible en esta versión"
                    )
                    plusFeatureRow(
                        icon: "book",
                        title: "Estudiar y aprender",
                        subtitle: "Próximamente"
                    )
                    plusFeatureRow(
                        icon: "cursorarrow.click",
                        title: "Modo agente",
                        subtitle: "Próximamente"
                    )
                }
                .padding(20)
            }
            .background(Color.black)
            .navigationTitle("Herramientas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func plusQuickButton(icon: String, title: String) -> some View {
        Button {
            onDismiss()
            dismiss()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.white)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                TeamAIGlassRoundedCardBackground(cornerRadius: 16)
            }
        }
        .buttonStyle(.plain)
    }

    private func plusFeatureRow(
        icon: String,
        title: String,
        subtitle: String,
        action: (() -> Void)? = nil
    ) -> some View {
        Button {
            if let action {
                action()
                dismiss()
            }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                Spacer(minLength: 0)
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .opacity(action == nil ? 0.65 : 1)
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
