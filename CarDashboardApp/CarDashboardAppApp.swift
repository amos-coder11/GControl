import SwiftUI

@main
struct CarDashboardAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authVM = AuthViewModel()
    @StateObject private var carsVM = CarsViewModel()
    @StateObject private var settingsVM = SettingsViewModel()
    @StateObject private var appLock = AppLockManager()

    var body: some Scene {
        WindowGroup {
            AppShellRoot(authVM: authVM)
                .environmentObject(carsVM)
                .environmentObject(settingsVM)
                .environmentObject(appLock)
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
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        AuthRootView(auth: authVM)
            .environmentObject(carsVM)
            .environmentObject(settingsVM)
            .environmentObject(appLock)
            .onAppear {
                syncAppLockWithSession()
            }
            .onChange(of: authVM.isAuthenticated) { _, _ in
                syncAppLockWithSession()
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
}
