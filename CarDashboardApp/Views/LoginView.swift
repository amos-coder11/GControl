import SwiftUI

// MARK: - Revolut-style auth (bienvenida + inicio / registro)

private enum AuthPhase {
    case welcome
    case signIn
    case signUp
}

private let authNavyTop = Color(red: 0.06, green: 0.14, blue: 0.32)
private let authLinkPurple = GrooBrand.primary
private let authDisabledPurple = Color(red: 0.72, green: 0.82, blue: 0.94)

private struct AuthSolidPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct LoginView: View {
    @ObservedObject var auth: AuthViewModel
    @EnvironmentObject private var moderation: UserModerationStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var phase: AuthPhase = .welcome
    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var showResetSheet = false
    @State private var resetEmail = ""
    @State private var resetInfo: String?
    @State private var showHelpAlert = false
    @State private var showTermsSheet = false
    @State private var pendingAuthAfterTerms = false
    @FocusState private var focusedField: AuthField?

    private enum AuthField: Hashable {
        case email
        case password
    }

    private var canSubmit: Bool {
        email.contains("@") && email.contains(".") && password.count >= 6
    }

    /// Ancho máximo del contenido en iPad / ventanas anchas (legible y centrado).
    private var authColumnMaxWidth: CGFloat {
        horizontalSizeClass == .regular ? 560 : .infinity
    }

    var body: some View {
        ZStack {
            switch phase {
            case .welcome:
                welcomeLayer
            case .signIn, .signUp:
                innerAuthLayer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.light)
        .animation(.easeInOut(duration: 0.25), value: phase)
        .sheet(isPresented: $showResetSheet) {
            resetPasswordSheet
        }
        .alert("Help", isPresented: $showHelpAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You'll be able to get help from here soon.")
        }
        .sheet(isPresented: $showTermsSheet) {
            UGCTermsAcceptanceSheet(isPresented: $showTermsSheet) {
                moderation.acceptTermsLocallyBeforeAuth()
                if pendingAuthAfterTerms {
                    pendingAuthAfterTerms = false
                    Task { await submitAuth() }
                }
            }
        }
    }

    // MARK: Welcome (fondo login + panel difuminado abajo)

    private var welcomeLayer: some View {
        ZStack(alignment: .bottom) {
            loginBackdropImage

            welcomeBottomFrost
        }
    }

    private var welcomeBottomFrost: some View {
        VStack(spacing: 14) {
            Button {
                phase = .signUp
                auth.clearAuthMessages()
            } label: {
                Text("Get started")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(red: 0.91, green: 0.95, blue: 1.0))
                    .foregroundStyle(GrooBrand.primary)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(GrooBrand.primary.opacity(0.2), lineWidth: 1)
                    }
            }
            .buttonStyle(AuthSolidPressStyle())

            Button {
                phase = .signIn
                auth.clearAuthMessages()
            } label: {
                Text("Sign in")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(GrooBrand.primary)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(AuthSolidPressStyle())
        }
        .frame(maxWidth: authColumnMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, horizontalSizeClass == .regular ? 40 : 20)
        .padding(.bottom, horizontalSizeClass == .regular ? 48 : 36)
    }

    private var authWhiteSheetBackground: some View {
        ZStack(alignment: .top) {
            Color.white
                .ignoresSafeArea(edges: .bottom)
            UnevenRoundedRectangle(
                topLeadingRadius: 28,
                topTrailingRadius: 28,
                style: .continuous
            )
            .fill(Color.white)
        }
    }

    // MARK: Inner (login / registro sobre fondo login)

    private var innerAuthLayer: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    circleNavButton(systemName: "chevron.left") {
                        phase = .welcome
                        auth.clearAuthMessages()
                    }
                    Spacer()
                    circleNavButton(systemName: "questionmark") {
                        showHelpAlert = true
                    }
                }
                .frame(maxWidth: authColumnMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, horizontalSizeClass == .regular ? 40 : 20)
                .padding(.top, 8)
                .padding(.bottom, 8)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        if phase == .signIn {
                            SectionHeader(
                                title: "Good to see you again",
                                subtitle: "Enter the email and password for your \(GrooBrand.appName) clinic account.",
                                lightOnDark: false
                            )
                        } else {
                            SectionHeader(
                                title: "Create your account",
                                subtitle: "Sign up to manage your dental clinic with \(GrooBrand.appName).",
                                lightOnDark: false
                            )
                        }

                        authPillField {
                            TextField(
                                "",
                                text: $email,
                                prompt: Text("Email address").foregroundStyle(DrflowTheme.textTertiary)
                            )
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(DrflowTheme.textPrimary)
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                        }

                        authPillField {
                            SecureField(
                                "",
                                text: $password,
                                prompt: Text("Password").foregroundStyle(DrflowTheme.textTertiary)
                            )
                            .textContentType(phase == .signUp ? .newPassword : .password)
                            .foregroundStyle(DrflowTheme.textPrimary)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit {
                                guard canSubmit, !isBusy else { return }
                                Task { await submitAuth() }
                            }
                        }

                        authFeedbackMessages

                        if phase == .signIn {
                            Button("Forgot your password?") {
                                resetEmail = email
                                showResetSheet = true
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(authLinkPurple)

                            Button("Don't have an account? Create account") {
                                phase = .signUp
                                auth.clearAuthMessages()
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(authLinkPurple)

                            Button("View Terms of Use (EULA)") {
                                showTermsSheet = true
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(authLinkPurple.opacity(0.85))
                        } else {
                            Button("Already have an account? Sign in") {
                                phase = .signIn
                                auth.clearAuthMessages()
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(authLinkPurple)
                        }

                        continueButton
                            .padding(.top, 4)

                        if phase == .signUp {
                            termsAcceptanceRow
                                .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: authColumnMaxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, horizontalSizeClass == .regular ? 40 : 20)
                    .padding(.top, 8)
                    .padding(.bottom, horizontalSizeClass == .regular ? 48 : 36)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .preferredColorScheme(.light)
        .toolbarBackground(.white, for: .navigationBar)
    }

    private var loginBackdropImage: some View {
        Image("FodoDeLogin")
            .resizable()
            .scaledToFill()
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .clipped()
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var authFeedbackMessages: some View {
        if let msg = auth.lastErrorMessage {
            Text(msg)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.red.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        } else if let msg = auth.lastInfoMessage {
            Text(msg)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(red: 0.45, green: 0.85, blue: 0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var continueButton: some View {
        Button {
            Task { await submitAuth() }
        } label: {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .tint(canSubmit ? GrooBrand.purple : .white.opacity(0.7))
                }
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(canSubmit && !isBusy ? GrooBrand.purple : authDisabledPurple)
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .disabled(!canSubmit || isBusy)
        .buttonStyle(AuthSolidPressStyle())
    }

    private var termsAcceptanceRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: moderation.hasAcceptedCurrentTerms ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(moderation.hasAcceptedCurrentTerms ? DrflowTheme.positive : DrflowTheme.textMuted)
                Text("You must accept the Terms of Use before creating an account. There is zero tolerance for objectionable content or abusive users.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DrflowTheme.textSecondary)
            }
            Button("View Terms of Use (EULA)") {
                showTermsSheet = true
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(authLinkPurple)
        }
    }

    private func submitAuth() async {
        focusedField = nil
        guard moderation.hasAcceptedCurrentTerms else {
            pendingAuthAfterTerms = true
            showTermsSheet = true
            return
        }
        isBusy = true
        defer { isBusy = false }
        if phase == .signUp {
            let outcome = await auth.signUp(email: email, password: password)
            switch outcome {
            case .signedIn:
                break
            case .emailConfirmationRequired, .existingAccount:
                phase = .signIn
            case .failed:
                break
            }
        } else {
            await auth.signIn(email: email, password: password)
        }
    }

    private func circleNavButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DrflowTheme.textPrimary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func authPillField<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(DrflowTheme.cardBorder, lineWidth: 1)
                    }
            )
    }

    private var resetPasswordSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $resetEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
                if let resetInfo {
                    Section {
                        Text(resetInfo)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Recover access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        showResetSheet = false
                        resetInfo = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        Task {
                            resetInfo = await auth.resetPassword(email: resetEmail)
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    LoginView(auth: AuthViewModel())
        .environmentObject(UserModerationStore())
}
