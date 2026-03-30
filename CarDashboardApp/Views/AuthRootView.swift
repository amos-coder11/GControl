import SwiftUI

/// Raíz: sesión Supabase → PIN inicial si hace falta → bloqueo Face ID/PIN → app principal.
struct AuthRootView: View {
    @ObservedObject var auth: AuthViewModel
    @EnvironmentObject var carsVM: CarsViewModel
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var appLock: AppLockManager

    var body: some View {
        Group {
            if auth.isRestoringSession {
                ZStack {
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()
                    ProgressView("Conectando…")
                }
            } else if auth.isAuthenticated {
                if !appLock.hasPINConfigured {
                    PINSetupView()
                } else if !appLock.isUnlocked {
                    LockScreenView()
                } else {
                    MainTabView()
                }
            } else {
                LoginView(auth: auth)
            }
        }
        .environmentObject(auth)
        .onOpenURL { url in
            SupabaseClientProvider.shared.auth.handle(url)
        }
    }
}

#Preview {
    AuthRootView(auth: AuthViewModel())
        .environmentObject(CarsViewModel())
        .environmentObject(SettingsViewModel())
        .environmentObject(AppLockManager())
}
