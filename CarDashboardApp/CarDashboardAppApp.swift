import SwiftUI

@main
struct CarDashboardAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authVM = AuthViewModel()
    @StateObject private var settingsVM = SettingsViewModel()
    @StateObject private var appLock = AppLockManager()
    @StateObject private var moderationStore = UserModerationStore()

    var body: some Scene {
        WindowGroup {
            AppShellRoot(authVM: authVM)
                .environmentObject(settingsVM)
                .environmentObject(appLock)
                .environmentObject(moderationStore)
                .preferredColorScheme(.light)
        }
    }
}

/// Encapsula ciclo de vida de la app y sincroniza sesión Supabase.
private struct AppShellRoot: View {
    @ObservedObject var authVM: AuthViewModel
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var appLock: AppLockManager
    @EnvironmentObject var moderationStore: UserModerationStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var phoneCallAlertMessage: String?

    var body: some View {
        AuthRootView(auth: authVM)
            .environmentObject(settingsVM)
            .environmentObject(appLock)
            .environmentObject(moderationStore)
            .onAppear {
                syncAppLockWithSession()
            }
            .onReceive(NotificationCenter.default.publisher(for: .phoneCallDidFail)) { note in
                let number = note.userInfo?["number"] as? String ?? ""
                let reason = note.userInfo?["reason"] as? String ?? "unavailable"
                if reason == "simulator" {
                    phoneCallAlertMessage =
                        "Las llamadas no funcionan en el simulador. Número copiado al portapapeles:\n\(number)"
                } else {
                    phoneCallAlertMessage =
                        "No se pudo abrir el teléfono. Número copiado al portapapeles:\n\(number)"
                }
            }
            .alert("Llamada", isPresented: Binding(
                get: { phoneCallAlertMessage != nil },
                set: { if !$0 { phoneCallAlertMessage = nil } }
            )) {
                Button("OK", role: .cancel) { phoneCallAlertMessage = nil }
            } message: {
                Text(phoneCallAlertMessage ?? "")
            }
            .onChange(of: authVM.isAuthenticated) { _, _ in
                syncAppLockWithSession()
                syncModerationWithSession()
            }
            .task(id: authVM.session?.user.id) {
                await syncModerationWithSessionAsync()
            }
            .task(id: authVM.isAuthenticated) {
                guard authVM.isAuthenticated else { return }
                await RemotePushRegistration.requestAuthorizationAndRegister()
                await RemotePushRegistration.syncPendingTokenToSupabase()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, authVM.isAuthenticated else { return }
                Task {
                    await RemotePushRegistration.refreshIfAuthorized()
                }
            }
    }

    private func syncAppLockWithSession() {
        if authVM.isAuthenticated, let uid = authVM.session?.user.id {
            appLock.setActiveUser(uid)
        } else {
            appLock.setActiveUser(nil)
        }
    }

    private func syncModerationWithSession() {
        Task { await syncModerationWithSessionAsync() }
    }

    private func syncModerationWithSessionAsync() async {
        if let uid = authVM.session?.user.id {
            await moderationStore.load(for: uid)
            if moderationStore.hasAcceptedCurrentTerms {
                _ = await moderationStore.acceptTerms(userId: uid)
            }
        } else {
            moderationStore.reset()
        }
    }
}
