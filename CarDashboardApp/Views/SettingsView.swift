import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsVM: SettingsViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                SectionHeader(title: "Ajustes", subtitle: "Configura tu experiencia")

                profileSection
                preferencesSection
                dataSection
                aboutSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(minWidth: 0, maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Profile
    private var profileSection: some View {
        GlassCard(cornerRadius: 24, padding: 20) {
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

                    Text(String(settingsVM.userName.prefix(1)))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(settingsVM.userName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)

                    Text("Plan Premium")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.cyan)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Preferences
    private var preferencesSection: some View {
        GlassCard(cornerRadius: 22, padding: 4) {
            VStack(spacing: 0) {
                settingsRow(
                    icon: "paintbrush.fill",
                    iconColor: .purple,
                    title: "Tema visual"
                ) {
                    Picker("", selection: $settingsVM.theme) {
                        ForEach(SettingsViewModel.AppTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.secondary)
                }

                settingsDivider

                settingsRow(
                    icon: "gauge.with.dots.needle.50percent",
                    iconColor: .cyan,
                    title: "Unidades de velocidad"
                ) {
                    Picker("", selection: $settingsVM.useMph) {
                        Text("km/h").tag(false)
                        Text("mph").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }

                settingsDivider

                settingsRow(
                    icon: "sparkles",
                    iconColor: .orange,
                    title: "Animaciones"
                ) {
                    Toggle("", isOn: $settingsVM.animationsEnabled)
                        .tint(.cyan)
                        .labelsHidden()
                }
            }
        }
    }

    // MARK: - Data
    private var dataSection: some View {
        GlassCard(cornerRadius: 22, padding: 4) {
            VStack(spacing: 0) {
                settingsRow(
                    icon: "antenna.radiowaves.left.and.right",
                    iconColor: .green,
                    title: "Datos simulados"
                ) {
                    Toggle("", isOn: $settingsVM.simulatedData)
                        .tint(.cyan)
                        .labelsHidden()
                }

                settingsDivider

                settingsRow(
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: .mint,
                    title: "Frecuencia de actualización"
                ) {
                    Text("1.5s")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - About
    private var aboutSection: some View {
        GlassCard(cornerRadius: 22, padding: 4) {
            VStack(spacing: 0) {
                settingsRow(
                    icon: "info.circle.fill",
                    iconColor: .blue,
                    title: "Versión"
                ) {
                    Text("\(settingsVM.appVersion) (\(settingsVM.buildNumber))")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                settingsDivider

                settingsRow(
                    icon: "swift",
                    iconColor: .orange,
                    title: "Desarrollado con"
                ) {
                    Text("SwiftUI")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                settingsDivider

                settingsRow(
                    icon: "heart.fill",
                    iconColor: .red,
                    title: "Valorar la app"
                ) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
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
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 32, height: 32)

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)

            Spacer()

            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var settingsDivider: some View {
        Divider()
            .overlay(Color.primary.opacity(0.1))
            .padding(.leading, 62)
    }
}

#Preview {
    ZStack {
        Color.white.ignoresSafeArea()
        SettingsView()
            .environmentObject(SettingsViewModel())
    }
}
