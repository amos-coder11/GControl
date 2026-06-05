import SwiftUI

/// Raíz: sesión Supabase → PIN inicial si hace falta → bloqueo Face ID/PIN → app principal.
struct AuthRootView: View {
    @ObservedObject var auth: AuthViewModel
    @EnvironmentObject var carsVM: CarsViewModel
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var appLock: AppLockManager
    @EnvironmentObject var moderationStore: UserModerationStore
    @State private var showPostAuthTerms = false

    var body: some View {
        Group {
            if auth.isRestoringSession {
                ZStack {
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()
                    ProgressView("Conectando…")
                }
            } else if auth.isAuthenticated {
                if !moderationStore.hasAcceptedCurrentTerms {
                    UGCTermsAcceptanceSheet(isPresented: $showPostAuthTerms) {
                        Task {
                            if let uid = auth.session?.user.id {
                                _ = await moderationStore.acceptTerms(userId: uid)
                            } else {
                                moderationStore.acceptTermsLocallyBeforeAuth()
                            }
                        }
                    }
                    .onAppear { showPostAuthTerms = true }
                } else if !appLock.hasPINConfigured {
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
