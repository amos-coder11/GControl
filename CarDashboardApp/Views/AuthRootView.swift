import SwiftUI

/// Raíz: sesión Supabase → términos UGC (si aplica) → flujo GROO (onboarding / CARE / app).
struct AuthRootView: View {
    @ObservedObject var auth: AuthViewModel
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var moderationStore: UserModerationStore
    @StateObject private var groo = GrooAppStore()
    @StateObject private var chatInbox = ChatInboxStore()
    @StateObject private var communityVM = DashboardCommunityViewModel()
    @StateObject private var chatNav = ChatNavigationCoordinator()
    @ObservedObject private var voicePlayback = ChatVoicePlaybackCoordinator.shared
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
                } else {
                    GrooRootFlow()
                        .environmentObject(groo)
                }
            } else {
                LoginView(auth: auth)
            }
        }
        .environmentObject(auth)
        .environmentObject(groo)
        .environmentObject(chatInbox)
        .environmentObject(communityVM)
        .environmentObject(chatNav)
        .environmentObject(voicePlayback)
        .onOpenURL { url in
            SupabaseClientProvider.shared.auth.handle(url)
        }
    }
}

#Preview {
    AuthRootView(auth: AuthViewModel())
        .environmentObject(SettingsViewModel())
        .environmentObject(AppLockManager())
}
