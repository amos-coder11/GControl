import SwiftUI

// MARK: - Revolut-style auth (bienvenida + inicio / registro)

private enum AuthPhase {
    case welcome
    case signIn
    case signUp
}

private let authNavyTop = Color(red: 0.04, green: 0.07, blue: 0.16)
private let authLinkBlue = Color(red: 0.35, green: 0.55, blue: 1.0)

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
    @State private var showComingSoonAlert = false
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
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: phase)
        .sheet(isPresented: $showResetSheet) {
            resetPasswordSheet
        }
        .alert("Ayuda", isPresented: $showHelpAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Próximamente podrás obtener ayuda desde aquí.")
        }
        .alert("Próximamente", isPresented: $showComingSoonAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Esta opción estará disponible en una próxima actualización.")
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

    // MARK: Welcome (fondo actual, CTA abajo)

    private var welcomeLayer: some View {
        ZStack {
            Image("ChatBackdropBase")
                .resizable()
                .scaledToFill()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Text("Carhub365")
                    .font(.system(size: horizontalSizeClass == .regular ? 34 : 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
                    .padding(.top, horizontalSizeClass == .regular ? 28 : 20)
                    .frame(maxWidth: .infinity)

                Spacer(minLength: 0)

                VStack(spacing: 14) {
                    Button {
                        phase = .signUp
                        auth.clearAuthMessages()
                    } label: {
                        Text("Crear cuenta")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white)
                            .foregroundStyle(.black)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        phase = .signIn
                        auth.clearAuthMessages()
                    } label: {
                        Text("Iniciar sesión")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.black)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: authColumnMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, horizontalSizeClass == .regular ? 40 : 20)
                .padding(.bottom, horizontalSizeClass == .regular ? 48 : 36)
            }
        }
    }

    // MARK: Inner (gradiente oscuro + misma imagen de base)

    private var innerAuthLayer: some View {
        ZStack {
            Image("ChatBackdropBase")
                .resizable()
                .scaledToFill()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()

            LinearGradient(
                colors: [authNavyTop.opacity(0.94), Color.black.opacity(0.97)],
                startPoint: .top,
                endPoint: .bottom
            )
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

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        if phase == .signIn {
                            SectionHeader(
                                title: "Nos alegra volver a verte",
                                subtitle: "Introduce el correo y la contraseña de tu cuenta CarDashboard.",
                                lightOnDark: true
                            )
                        } else {
                            SectionHeader(
                                title: "Crea tu cuenta",
                                subtitle: "Regístrate con tu correo para guardar tu garaje y sincronizar datos.",
                                lightOnDark: true
                            )
                        }

                        authPillField {
                            TextField(
                                "",
                                text: $email,
                                prompt: Text("Correo electrónico").foregroundStyle(.white.opacity(0.42))
                            )
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(.white)
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                        }

                        authPillField {
                            SecureField(
                                "",
                                text: $password,
                                prompt: Text("Contraseña").foregroundStyle(.white.opacity(0.42))
                            )
                            .textContentType(phase == .signUp ? .newPassword : .password)
                            .foregroundStyle(.white)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit {
                                guard canSubmit, !isBusy else { return }
                                Task { await submitAuth() }
                            }
                        }

                        authFeedbackMessages

                        if phase == .signIn {
                            Button("¿Olvidaste la contraseña?") {
                                resetEmail = email
                                showResetSheet = true
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(authLinkBlue)

                        Button("¿No tienes cuenta? Crear cuenta") {
                            phase = .signUp
                            auth.clearAuthMessages()
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(authLinkBlue)

                        Button("Ver Términos de uso (EULA)") {
                            showTermsSheet = true
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(authLinkBlue.opacity(0.85))
                        } else {
                            Button("¿Ya tienes cuenta? Iniciar sesión") {
                                phase = .signIn
                                auth.clearAuthMessages()
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(authLinkBlue)
                        }

                        continueButton
                            .padding(.top, 4)

                        if phase == .signUp {
                            termsAcceptanceRow
                                .padding(.top, 2)
                        }

                        authOrSeparator
                            .padding(.top, 4)

                        VStack(spacing: 12) {
                            secondaryAuthRow(icon: "key.fill", title: "Continuar con passkey") {
                                showComingSoonAlert = true
                            }
                            secondaryAuthRow(icon: "g.circle.fill", title: "Continuar con Google") {
                                showComingSoonAlert = true
                            }
                            secondaryAuthRow(icon: "apple.logo", title: "Continuar con Apple") {
                                showComingSoonAlert = true
                            }
                        }
                    }
                    .frame(maxWidth: authColumnMaxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, horizontalSizeClass == .regular ? 40 : 20)
                    .padding(.top, 20)
                    .padding(.bottom, horizontalSizeClass == .regular ? 48 : 28)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
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
                        .tint(canSubmit ? .black : .white.opacity(0.4))
                }
                Text("Continuar")
                    .font(.system(size: 17, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(canSubmit && !isBusy ? Color.white : Color.white.opacity(0.14))
            .foregroundStyle(canSubmit && !isBusy ? Color.black : Color.white.opacity(0.38))
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .disabled(!canSubmit || isBusy)
        .buttonStyle(.plain)
    }

    private var termsAcceptanceRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: moderation.hasAcceptedCurrentTerms ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(moderation.hasAcceptedCurrentTerms ? Color.green : Color.white.opacity(0.45))
                Text("Debes aceptar los Términos de uso antes de crear cuenta. No hay tolerancia para contenido objetable ni usuarios abusivos.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.72))
            }
            Button("Ver Términos de uso (EULA)") {
                showTermsSheet = true
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(authLinkBlue)
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

    private var authOrSeparator: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(height: 1)
            Text("o")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.45))
            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(height: 1)
        }
    }

    private func circleNavButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.12)))
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
                    .fill(Color.white.opacity(0.10))
            )
    }

    private func secondaryAuthRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 24, alignment: .center)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
    }

    private var resetPasswordSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Correo", text: $resetEmail)
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
            .navigationTitle("Recuperar acceso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        showResetSheet = false
                        resetInfo = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enviar") {
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
