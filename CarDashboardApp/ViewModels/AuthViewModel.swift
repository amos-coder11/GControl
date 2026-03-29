import Combine
import Foundation
import Supabase

@MainActor
final class AuthViewModel: ObservableObject {
    private let client: SupabaseClient

    @Published private(set) var session: Session?
    @Published private(set) var isRestoringSession = true
    @Published var lastErrorMessage: String?

    private var authStateTask: Task<Void, Never>?

    init(client: SupabaseClient = SupabaseClientProvider.shared) {
        self.client = client
        session = client.auth.currentSession
        isRestoringSession = session == nil
        startAuthStateListener()
        Task { await refreshSessionIfNeeded() }
    }

    deinit {
        authStateTask?.cancel()
    }

    var isAuthenticated: Bool {
        session != nil
    }

    var userEmail: String? {
        session?.user.email
    }

    var userDisplayName: String {
        if let email = userEmail, !email.isEmpty {
            return email
        }
        return "Invitado"
    }

    private func startAuthStateListener() {
        authStateTask?.cancel()
        authStateTask = Task { [client] in
            for await (_, newSession) in client.auth.authStateChanges {
                await MainActor.run {
                    self.session = newSession
                    self.isRestoringSession = false
                }
            }
        }
    }

    private func refreshSessionIfNeeded() async {
        defer { isRestoringSession = false }
        do {
            let s = try await client.auth.session
            await MainActor.run { self.session = s }
        } catch {
            await MainActor.run { self.session = client.auth.currentSession }
        }
    }

    func signIn(email: String, password: String) async {
        lastErrorMessage = nil
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !password.isEmpty else {
            lastErrorMessage = "Introduce correo y contraseña."
            return
        }
        do {
            let s = try await client.auth.signIn(email: trimmed, password: password)
            session = s
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func signUp(email: String, password: String) async {
        lastErrorMessage = nil
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !password.isEmpty else {
            lastErrorMessage = "Introduce correo y contraseña."
            return
        }
        do {
            let response = try await client.auth.signUp(email: trimmed, password: password)
            if let s = response.session {
                session = s
            } else {
                lastErrorMessage =
                    "Cuenta creada. Si el proyecto exige confirmar el correo, revisa tu bandeja de entrada."
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        lastErrorMessage = nil
        do {
            try await client.auth.signOut()
            session = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func resetPassword(email: String) async -> String? {
        lastErrorMessage = nil
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastErrorMessage = "Introduce tu correo."
            return nil
        }
        do {
            try await client.auth.resetPasswordForEmail(trimmed)
            return "Si existe una cuenta con ese correo, recibirás un enlace para restablecer la contraseña."
        } catch {
            lastErrorMessage = error.localizedDescription
            return nil
        }
    }
}
