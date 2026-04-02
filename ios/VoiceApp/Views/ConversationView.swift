import Combine
import SwiftUI

/// Full-screen voice session UI: mic control, status, transcript, errors, and settings.
struct ConversationView: View {
    @StateObject private var viewModel: ConversationViewModel
    @State private var showSettings = false
    @State private var pulseScale: CGFloat = 1.0

    @AppStorage("VoiceApp.selectedEnvironment") private var environmentRawValue: String = AppEnvironment.dev.rawValue

    init(environment: AppEnvironment) {
        let audio = AudioService()
        let rtc = WebRTCService()
        let session = SessionService(webRTC: rtc)
        _viewModel = StateObject(
            wrappedValue: ConversationViewModel(
                environment: environment,
                audioService: audio,
                webRTCService: rtc,
                sessionService: session
            )
        )
    }

    var body: some View {
        ZStack {
            Color("VoiceBackground")
                .ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundStyle(Color("VoiceAccent"))
                    }
                    .accessibilityLabel(VoiceStrings.Accessibility.settingsButton)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Text(VoiceStrings.UI.conversationTitle)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.primary)

                Text(SessionStateFormatter.statusLine(for: viewModel.sessionState))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                micButton
                    .padding(.vertical, 16)

                if case .error(let err) = viewModel.sessionState {
                    ErrorBannerView(message: err.localizedDescription) {
                        viewModel.acknowledgeError()
                    }
                    .padding(.horizontal)
                }

                transcriptSection
                    .padding(.horizontal)

                Spacer(minLength: 0)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheetView(
                environmentRawValue: $environmentRawValue
            )
        }
        .onReceive(viewModel.$isModelSpeaking) { speaking in
            if speaking, case .connected = viewModel.sessionState {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulseScale = 1.08
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    pulseScale = 1.0
                }
            }
        }
    }

    private var micButton: some View {
        let isConnected = {
            if case .connected = viewModel.sessionState { return true }
            return false
        }()

        return Button {
            Task {
                switch viewModel.sessionState {
                case .idle, .error:
                    await viewModel.startSession()
                case .connected:
                    await viewModel.stopSession()
                default:
                    break
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color("VoiceAccent").opacity(0.25))
                    .frame(width: 120, height: 120)
                    .scaleEffect(isConnected ? pulseScale : 1.0)
                Circle()
                    .fill(Color("VoiceAccent"))
                    .frame(width: 88, height: 88)
                    .overlay {
                        Image(systemName: isConnected ? "stop.fill" : "mic.fill")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .disabled(isStartStopDisabled)
        .accessibilityLabel(VoiceStrings.Accessibility.micButton)
        .accessibilityHint(
            isConnected
                ? VoiceStrings.Accessibility.micHintStop
                : VoiceStrings.Accessibility.micHintStart
        )
    }

    private var isStartStopDisabled: Bool {
        switch viewModel.sessionState {
        case .requestingPermission, .fetchingToken, .connecting, .disconnecting:
            return true
        default:
            return false
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(VoiceStrings.UI.transcriptSectionTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(
                    viewModel.lastTranscript.isEmpty
                        ? VoiceStrings.UI.transcriptPlaceholder
                        : viewModel.lastTranscript
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.body)
                .foregroundStyle(viewModel.lastTranscript.isEmpty ? .tertiary : .primary)
            }
            .frame(minHeight: 160, maxHeight: 280)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
        }
    }
}

/// Backend URL and environment overrides (persisted).
private struct SettingsSheetView: View {
    @Binding var environmentRawValue: String
    @Environment(\.dismiss) private var dismiss
    @State private var backendURLField: String = ""
    @FocusState private var urlFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section(VoiceStrings.UI.settingsEnvironment) {
                    Picker(VoiceStrings.UI.settingsEnvironment, selection: $environmentRawValue) {
                        ForEach(AppEnvironment.allCases) { env in
                            Text(env.rawValue.capitalized).tag(env.rawValue)
                        }
                    }
                }
                Section(VoiceStrings.UI.settingsBackendURL) {
                    TextField(VoiceStrings.UI.backendURLPlaceholder, text: $backendURLField)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($urlFocused)
                }
            }
            .navigationTitle(VoiceStrings.UI.settingsTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(VoiceStrings.UI.settingsDismiss) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(VoiceStrings.UI.settingsSave) {
                        AppConfig.setCustomBackendBaseURL(backendURLField)
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let existing = UserDefaults.standard.string(forKey: "VoiceApp.customBackendBaseURL") {
                    backendURLField = existing
                }
            }
        }
    }
}
