import SwiftUI

struct LoginView: View {
    @ObservedObject var auth: AuthViewModel

    @State private var email = ""
    @State private var password = ""
    @State private var isRegisterMode = false
    @State private var isBusy = false
    @State private var showResetSheet = false
    @State private var resetEmail = ""
    @State private var resetInfo: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 22) {
                SectionHeader(
                    title: isRegisterMode ? "Crear cuenta" : "Entrar",
                    subtitle: "Conexión segura con Supabase"
                )

                GlassCard(cornerRadius: 24, padding: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Correo")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField("tu@email.com", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Text("Contraseña")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        SecureField("••••••••", text: $password)
                            .textContentType(isRegisterMode ? .newPassword : .password)

                        if let msg = auth.lastErrorMessage {
                            Text(msg)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.red.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button {
                            Task {
                                isBusy = true
                                defer { isBusy = false }
                                if isRegisterMode {
                                    await auth.signUp(email: email, password: password)
                                } else {
                                    await auth.signIn(email: email, password: password)
                                }
                            }
                        } label: {
                            HStack {
                                if isBusy {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(isRegisterMode ? "Registrarse" : "Iniciar sesión")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: [PremiumAccent.ice, PremiumAccent.mint],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(isBusy)

                        Button(isRegisterMode ? "¿Ya tienes cuenta? Entrar" : "¿No tienes cuenta? Registrarse") {
                            isRegisterMode.toggle()
                            auth.lastErrorMessage = nil
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(PremiumAccent.tabActive)
                        .frame(maxWidth: .infinity)

                        if !isRegisterMode {
                            Button("¿Olvidaste la contraseña?") {
                                resetEmail = email
                                showResetSheet = true
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showResetSheet) {
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
}

#Preview {
    LoginView(auth: AuthViewModel())
}
