import SwiftUI

@main
struct CarDashboardAppApp: App {
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
    }

    private func syncAppLockWithSession() {
        if authVM.isAuthenticated {
            appLock.refreshPINState()
        } else {
            appLock.clearPIN()
        }
    }
}
