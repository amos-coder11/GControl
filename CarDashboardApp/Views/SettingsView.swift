import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var auth: AuthViewModel

    @AppStorage(VehicleImageDiagnostics.userDefaultsKey) private var logVehicleImageDiagnostics = false

    @State private var settingsSearchText = ""
    @FocusState private var settingsSearchFieldFocused: Bool
    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?

    var body: some View {
        RevolutChromeContainer {
            VStack(spacing: 0) {
                AppChromeHeaderRow(
                    initials: auth.userInitials,
                    profileImage: auth.profileAvatarImage,
                    searchText: $settingsSearchText,
                    prompt: Text("Buscar")
                        .foregroundStyle(.white.opacity(DashboardChromeSearchFieldStyle.promptOpacity)),
                    showsSearchClearButton: true,
                    searchFieldFocused: $settingsSearchFieldFocused
                ) {
                    HStack(spacing: AppChromeHeaderMetrics.hStackSpacing) {
                        AppChromeHeaderCircleIconButton(
                            systemName: "chart.bar.fill",
                            accessibilityLabel: "Estadísticas",
                            action: {}
                        )
                        AppChromeHeaderCircleIconButton(
                            systemName: "bell.fill",
                            accessibilityLabel: "Notificaciones",
                            action: {}
                        )
                    }
                }
                .appChromeHeaderOuterPadding()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        profileSection
                        if auth.isAuthenticated {
                            notificationsSection
                        }
                        developerSection
                        accountSection
                        aboutSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                    .frame(minWidth: 0, maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                LiquidGlassKeyboardAccessoryBar {
                    settingsSearchFieldFocused = false
                }
            }
        }
        .task(id: auth.session?.user.id) {
            guard let uid = auth.session?.user.id else { return }
            await settingsVM.loadNotifyTeamPush(
                client: SupabaseClientProvider.shared,
                userId: uid
            )
        }
        .confirmationDialog(
            "Eliminar cuenta",
            isPresented: $showDeleteAccountConfirm,
            titleVisibility: .visible
        ) {
            Button("Eliminar cuenta", role: .destructive) {
                Task {
                    isDeletingAccount = true
                    defer { isDeletingAccount = false }
                    do {
                        try await auth.deleteCurrentAccount()
                    } catch {
                        deleteAccountError = error.localizedDescription
                    }
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Esta acción elimina tu cuenta y no se puede deshacer.")
        }
        .alert("No se pudo eliminar la cuenta", isPresented: Binding(
            get: { deleteAccountError != nil },
            set: { if !$0 { deleteAccountError = nil } }
        )) {
            Button("Aceptar", role: .cancel) { deleteAccountError = nil }
        } message: {
            Text(deleteAccountError ?? "")
        }
    }

    // MARK: - Notificaciones

    private var notificationsSection: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Notificaciones")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))

                Toggle(
                    isOn: Binding(
                        get: { settingsVM.notifyTeamPushEnabled },
                        set: { new in
                            settingsVM.notifyTeamPushEnabled = new
                            if let uid = auth.session?.user.id {
                                Task {
                                    await settingsVM.persistNotifyTeamPush(
                                        new,
                                        client: SupabaseClientProvider.shared,
                                        userId: uid
                                    )
                                }
                            }
                        }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Avisos del equipo y tareas")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                        Text(
                            "Recibir push cuando te envíen un mensaje directo, aviso de grupo o una tarea desde Viera. Desactívalo si no quieres notificaciones en este dispositivo."
                        )
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(PremiumAccent.tabActive)
            }
        }
    }

    // MARK: - Profile

    private var profileSection: some View {
        ChromeSettingsCard(cornerRadius: 24, padding: 20) {
            HStack(spacing: 16) {
                ZStack {
                    if let photo = auth.profileAvatarImage {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.cyan.opacity(0.5), .purple.opacity(0.4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text(String(auth.userDisplayName.prefix(1)).uppercased())
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(auth.userDisplayName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Sesión Supabase")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PremiumAccent.ice.opacity(0.92))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    // MARK: - Desarrollo (diagnóstico imágenes)

    private var developerSection: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Desarrollo")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))

                Toggle(isOn: $logVehicleImageDiagnostics) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Diagnóstico de imágenes (consola Xcode)")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                        Text(
                            "Al cargar Coches se imprimen columnas JSON, rutas Storage, user_id y cuántos slots ve la UI. Abre la consola con ⌘⇧Y y tira hacia abajo para refrescar el listado."
                        )
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(PremiumAccent.tabActive)
            }
        }
    }

    // MARK: - Cuenta

    private var accountSection: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 4) {
            VStack(spacing: 0) {
                Button {
                    showDeleteAccountConfirm = true
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .environment(\.colorScheme, .dark)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                                }
                            Image(systemName: "trash.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.red.opacity(0.95))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isDeletingAccount ? "Eliminando cuenta..." : "Eliminar cuenta")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white)
                            Text("Borra permanentemente tu cuenta de CarHub.")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                        if isDeletingAccount {
                            ProgressView()
                                .tint(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .disabled(isDeletingAccount)

                Divider()
                    .overlay(Color.white.opacity(0.08))
                    .padding(.leading, 62)

                Button {
                    Task { await auth.signOut() }
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .environment(\.colorScheme, .dark)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                                }
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.red.opacity(0.95))
                        }
                        Text("Cerrar sesión")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Acerca de

    private var aboutSection: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 4) {
            VStack(spacing: 0) {
                settingsRow(
                    icon: "info.circle.fill",
                    iconColor: PremiumAccent.tabActive,
                    title: "Versión"
                ) {
                    Text("\(settingsVM.appVersion) (\(settingsVM.buildNumber))")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }

    // MARK: - Helpers

    private func settingsRow<Trailing: View>(
        icon: String,
        iconColor: Color,
        title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .frame(width: 32, height: 32)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    }

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsViewModel())
        .environmentObject(AuthViewModel())
}
