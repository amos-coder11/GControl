import Combine
import Foundation
import SwiftUI
import WebRTC

/// Orchestrates microphone, backend token, WebRTC session, and transcript UI state.
@MainActor
final class ConversationViewModel: ObservableObject {
    enum SessionState {
        case idle
        case requestingPermission
        case fetchingToken
        case connecting
        case connected
        case disconnecting
        case error(AppError)
    }

    @Published var sessionState: SessionState = .idle
    @Published var lastTranscript: String = ""
    @Published var isModelSpeaking: Bool = false

    private let environment: AppEnvironment
    private let audioService: AudioServiceProtocol
    private let webRTCService: WebRTCServiceProtocol
    private let sessionService: SessionServiceProtocol
    private let transcriptStore = TranscriptStore()
    private var cancellables = Set<AnyCancellable>()
    private var iceWasConnected = false

    init(
        environment: AppEnvironment,
        audioService: AudioServiceProtocol,
        webRTCService: WebRTCServiceProtocol,
        sessionService: SessionServiceProtocol
    ) {
        self.environment = environment
        self.audioService = audioService
        self.webRTCService = webRTCService
        self.sessionService = sessionService
    }

    /// Starts permission → audio session → backend token → WebRTC → OpenAI SDP.
    func startSession() async {
        guard case .idle = sessionState else { return }

        sessionState = .requestingPermission
        iceWasConnected = false
        await transcriptStore.reset()
        lastTranscript = ""
        isModelSpeaking = false

        let granted = await audioService.requestPermission()
        guard granted else {
            sessionState = .error(.microphonePermissionDenied)
            return
        }

        do {
            try audioService.setup()
        } catch {
            sessionState = .error(.audioSessionSetupFailed(underlying: error))
            return
        }

        sessionState = .fetchingToken

        let baseURL: URL
        do {
            baseURL = try AppConfig.resolvedBaseURL(environment: environment)
        } catch {
            sessionState = .error(.sessionTokenFetchFailed(underlying: error))
            return
        }

        let backend = BackendClient(session: URLSession.shared, baseURL: baseURL)

        sessionState = .connecting
        subscribeToRealtimeEvents()

        do {
            try await sessionService.start(with: backend)
        } catch let appErr as AppError {
            cancellables.removeAll()
            await sessionService.stop()
            audioService.tearDown()
            sessionState = .error(appErr)
            return
        } catch {
            cancellables.removeAll()
            await sessionService.stop()
            audioService.tearDown()
            sessionState = .error(.unknown(underlying: error))
            return
        }

        sessionState = .connected
    }

    /// Clears `.error` so the user can retry.
    func acknowledgeError() {
        if case .error = sessionState {
            sessionState = .idle
        }
    }

    /// Tears down WebRTC and audio when a session is active.
    func stopSession() async {
        switch sessionState {
        case .fetchingToken, .connecting, .connected:
            break
        default:
            return
        }

        sessionState = .disconnecting
        cancellables.removeAll()
        await sessionService.stop()
        audioService.tearDown()
        isModelSpeaking = false
        sessionState = .idle
    }

    private func subscribeToRealtimeEvents() {
        cancellables.removeAll()

        webRTCService.dataChannelMessagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                guard let self else { return }
                Task { await self.handleDataChannelMessage(data) }
            }
            .store(in: &cancellables)

        webRTCService.connectionStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleIceConnectionState(state)
            }
            .store(in: &cancellables)
    }

    private func handleDataChannelMessage(_ data: Data) async {
        let parsed = RealtimeEventParser.parse(data: data)

        switch parsed.type {
        case .sessionCreated, .sessionUpdated:
            Logger.info("Realtime session event: \(parsed.type?.rawValue ?? "")")
        case .responseAudioTranscriptDelta:
            if let delta = parsed.transcriptDelta {
                let full = await transcriptStore.append(delta)
                lastTranscript = full
            }
        case .responseOutputAudioDelta, .responseAudioDelta:
            if parsed.modelSpeakingHint == true {
                isModelSpeaking = true
            }
        case .responseDone:
            isModelSpeaking = false
        case .error:
            let err = NSError(domain: "OpenAIRealtime", code: 1, userInfo: [NSLocalizedDescriptionKey: "Server error event"])
            sessionState = .error(.unknown(underlying: err))
        case .none:
            break
        }
    }

    private func handleIceConnectionState(_ state: RTCIceConnectionState) {
        switch state {
        case .connected, .completed:
            iceWasConnected = true
        case .failed:
            switch sessionState {
            case .connecting, .connected:
                sessionState = .error(.iceConnectionFailed)
            default:
                break
            }
        case .disconnected:
            if iceWasConnected {
                switch sessionState {
                case .connected:
                    sessionState = .error(.iceConnectionFailed)
                default:
                    break
                }
            }
        default:
            break
        }
    }
}
