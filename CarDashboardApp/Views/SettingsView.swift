import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var moderation: UserModerationStore
    @EnvironmentObject var communityVM: DashboardCommunityViewModel

    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
    @State private var showTermsSheet = false

    var body: some View {
        RevolutChromeContainer {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    Text("Settings")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(DrflowTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)

                    profileSection
                    if auth.isAuthenticated {
                        notificationsSection
                        communitySafetySection
                    }
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
        .toolbar(.visible, for: .tabBar)
        .toolbarBackground(.hidden, for: .tabBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task(id: auth.session?.user.id) {
            guard let uid = auth.session?.user.id else { return }
            await settingsVM.loadNotifyTeamPush(
                client: SupabaseClientProvider.shared,
                userId: uid
            )
        }
        .confirmationDialog(
            "Delete account",
            isPresented: $showDeleteAccountConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
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
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action deletes your account and cannot be undone.")
        }
        .alert("Could not delete account", isPresented: Binding(
            get: { deleteAccountError != nil },
            set: { if !$0 { deleteAccountError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteAccountError = nil }
        } message: {
            Text(deleteAccountError ?? "")
        }
        .sheet(isPresented: $showTermsSheet) {
            UGCTermsView()
        }
    }

    // MARK: - Comunidad y seguridad

    private var communitySafetySection: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 4) {
            VStack(spacing: 0) {
                Button {
                    showTermsSheet = true
                } label: {
                    settingsRow(
                        icon: "doc.text.fill",
                        iconColor: PremiumAccent.tabActive,
                        title: "Terms of Use (EULA)"
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DrflowTheme.textMuted)
                    }
                }
                .buttonStyle(.plain)

                if !moderation.blockedUserIds.isEmpty {
                    Divider()
                        .overlay(DrflowTheme.separator)
                        .padding(.leading, 62)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Blocked users")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DrflowTheme.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 6)

                        ForEach(Array(moderation.blockedUserIds).sorted { $0.uuidString < $1.uuidString }, id: \.self) { uid in
                            let name = communityVM.directory.first(where: { $0.userId == uid })?.resolvedDisplayName ?? "User"
                            HStack {
                                Text(name)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(DrflowTheme.textPrimary)
                                Spacer()
                                Button("Unblock") {
                                    Task { await moderation.unblockUser(uid) }
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(red: 0.45, green: 0.72, blue: 1.0))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                    }
                }

                Divider()
                    .overlay(DrflowTheme.separator)
                    .padding(.leading, 62)

                settingsRow(
                    icon: "shield.lefthalf.filled",
                    iconColor: Color(red: 0.45, green: 0.88, blue: 0.62),
                    title: "Moderation"
                ) {
                    EmptyView()
                }
                .overlay(alignment: .bottom) {
                    Text("Reports reviewed within 24h. You can report or block from any chat.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(DrflowTheme.textTertiary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .offset(y: 28)
                }
                .padding(.bottom, 28)
            }
        }
    }

    // MARK: - Notificaciones

    private var notificationsSection: some View {
        ChromeSettingsCard(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Notifications")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DrflowTheme.textSecondary)

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
                        Text("Team alerts and tasks")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(DrflowTheme.textPrimary)
                        Text(
                            "Recibe avisos de mensajes de Instagram, del equipo y tareas de Viera. Necesitas un iPhone real y tener notificaciones activadas para GControl."
                        )
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(DrflowTheme.textSecondary)
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
                            .foregroundStyle(DrflowTheme.textPrimary)
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(auth.userDisplayName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(DrflowTheme.textPrimary)

                    Text("Supabase session")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PremiumAccent.ice.opacity(0.92))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DrflowTheme.textTertiary)
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
                                .fill(DrflowTheme.controlFill)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(DrflowTheme.cardBorder, lineWidth: 0.5)
                                }
                            Image(systemName: "trash.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.red.opacity(0.95))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isDeletingAccount ? "Deleting account..." : "Delete account")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(DrflowTheme.textPrimary)
                            Text("Permanently deletes your \(GrooBrand.appName) account.")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(DrflowTheme.textSecondary)
                        }
                        Spacer()
                        if isDeletingAccount {
                            ProgressView()
                                .tint(PremiumAccent.tabActive)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .disabled(isDeletingAccount)

                Divider()
                    .overlay(DrflowTheme.separator)
                    .padding(.leading, 62)

                Button {
                    Task { await auth.signOut() }
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(DrflowTheme.controlFill)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(DrflowTheme.cardBorder, lineWidth: 0.5)
                                }
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.red.opacity(0.95))
                        }
                        Text("Sign out")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(DrflowTheme.textPrimary)
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
                    title: "Version"
                ) {
                    Text("\(settingsVM.appVersion) (\(settingsVM.buildNumber))")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DrflowTheme.textSecondary)
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
                    .fill(DrflowTheme.controlFill)
                    .frame(width: 32, height: 32)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(DrflowTheme.cardBorder, lineWidth: 0.5)
                    }

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DrflowTheme.textPrimary)

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
        .environmentObject(UserModerationStore())
        .environmentObject(DashboardCommunityViewModel())
}
