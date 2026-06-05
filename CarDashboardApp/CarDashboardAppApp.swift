import SwiftUI

@main
struct CarDashboardAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authVM = AuthViewModel()
    @StateObject private var carsVM = CarsViewModel()
    @StateObject private var settingsVM = SettingsViewModel()
    @StateObject private var appLock = AppLockManager()
    @StateObject private var moderationStore = UserModerationStore()

    var body: some Scene {
        WindowGroup {
            AppShellRoot(authVM: authVM)
                .environmentObject(carsVM)
                .environmentObject(settingsVM)
                .environmentObject(appLock)
                .environmentObject(moderationStore)
                .preferredColorScheme(.dark)
        }
    }
}

/// Encapsula `scenePhase` y sincroniza el bloqueo local con la sesión Supabase.
private struct AppShellRoot: View {
    @ObservedObject var authVM: AuthViewModel
    @EnvironmentObject var carsVM: CarsViewModel
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var appLock: AppLockManager
    @EnvironmentObject var moderationStore: UserModerationStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        AuthRootView(auth: authVM)
            .environmentObject(carsVM)
            .environmentObject(settingsVM)
            .environmentObject(appLock)
            .environmentObject(moderationStore)
            .onAppear {
                syncAppLockWithSession()
            }
            .onChange(of: authVM.isAuthenticated) { _, _ in
                syncAppLockWithSession()
                syncModerationWithSession()
            }
            .task(id: authVM.session?.user.id) {
                await syncModerationWithSessionAsync()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    appLock.lock()
                }
            }
            // Evita el diálogo de notificaciones (y posibles conflictos de ventana) durante «Crea tu PIN» o la pantalla de bloqueo.
            .task(id: "\(authVM.isAuthenticated)-\(appLock.hasPINConfigured)-\(appLock.isUnlocked)") {
                guard authVM.isAuthenticated, appLock.hasPINConfigured, appLock.isUnlocked else { return }
                await RemotePushRegistration.requestAuthorizationAndRegister()
                await RemotePushRegistration.syncPendingTokenToSupabase()
            }
    }

    private func syncAppLockWithSession() {
        if authVM.isAuthenticated, let uid = authVM.session?.user.id {
            appLock.setActiveUser(uid)
        } else {
            // Cerrar sesión no borra el PIN en el llavero: cada usuario conserva su código en este dispositivo.
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
