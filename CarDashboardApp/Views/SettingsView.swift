import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var auth: AuthViewModel

    @State private var settingsSearchText = ""
    @FocusState private var settingsSearchFieldFocused: Bool

    var body: some View {
        RevolutChromeContainer {
            VStack(spacing: 0) {
                AppChromeHeaderRow(
                    initials: auth.userInitials,
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
    }

    // MARK: - Profile

    private var profileSection: some View {
        ChromeSettingsCard(cornerRadius: 24, padding: 20) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.cyan.opacity(0.5), .purple.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)

                    Text(String(auth.userDisplayName.prefix(1)).uppercased())
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

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

    // MARK: - Cuenta

    private var accountSection: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 4) {
            VStack(spacing: 0) {
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
