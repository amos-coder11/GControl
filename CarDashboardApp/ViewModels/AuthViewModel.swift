import Combine
import Foundation
import Supabase
import UIKit

/// Resultado de intentar crear cuenta (para que la UI reaccione sin confundir éxito con error).
enum SignUpOutcome: Equatable {
    case signedIn
    case emailConfirmationRequired
    case existingAccount
    case failed
}

@MainActor
final class AuthViewModel: ObservableObject {
    private let client: SupabaseClient

    @Published private(set) var session: Session?
    @Published private(set) var isRestoringSession = true
    @Published var lastErrorMessage: String?
    /// Mensajes informativos (éxito parcial, cuenta existente, etc.) — no son errores.
    @Published var lastInfoMessage: String?
    /// Foto de perfil del usuario con sesión iniciada (`profiles.avatar_url` o metadatos OAuth).
    @Published private(set) var profileAvatarImage: UIImage?
    /// Empresa del usuario autenticado (cargada desde `profiles.company_id` vía RPC).
    @Published private(set) var companyId: UUID?
    /// Organización del usuario autenticado (cargada desde `user_profiles.organization_id`).
    @Published private(set) var organizationId: UUID?

    private var authStateTask: Task<Void, Never>?
    private var profileAvatarTask: Task<Void, Never>?
    private var companyIdTask: Task<Void, Never>?
    private var organizationIdTask: Task<Void, Never>?
    private static let aiBlockedOrganizationIDs: Set<UUID> = [
        UUID(uuidString: "1d8bfc03-fa2b-419c-9f2a-bcce92651c5d")!,
    ]

    init(client: SupabaseClient = SupabaseClientProvider.shared) {
        self.client = client
        session = client.auth.currentSession
        isRestoringSession = session == nil
        startAuthStateListener()
        Task { await refreshSessionIfNeeded() }
        scheduleProfileAvatarLoad()
        scheduleCompanyIdLoad()
        scheduleOrganizationIdLoad()
    }

    deinit {
        authStateTask?.cancel()
        companyIdTask?.cancel()
        organizationIdTask?.cancel()
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

    /// Nombre corto para saludo (parte local del correo, legible).
    var shortGreetingName: String {
        guard let email = userEmail, !email.isEmpty else { return "Invitado" }
        guard let at = email.firstIndex(of: "@") else { return email }
        let local = String(email[..<at])
        let parts = local.split { $0 == "." || $0 == "_" || $0 == "-" }
        let words = parts.map { String($0).capitalized }.filter { !$0.isEmpty }
        if words.isEmpty { return "Invitado" }
        return words.joined(separator: " ")
    }

    var userInitials: String {
        let name = shortGreetingName
        let parts = name.split(separator: " ")
        if parts.count >= 2, let a = parts[0].first, let b = parts[1].first {
            return "\(a)\(b)".uppercased()
        }
        if let f = name.first { return String(f).uppercased() }
        return "?"
    }

    var canAccessIASection: Bool {
        guard let organizationId else { return true }
        return !Self.aiBlockedOrganizationIDs.contains(organizationId)
    }

    var canAccessTeamLocationSection: Bool {
        guard let organizationId else { return true }
        return !Self.aiBlockedOrganizationIDs.contains(organizationId)
    }

    private func startAuthStateListener() {
        authStateTask?.cancel()
        authStateTask = Task { [client] in
            for await (_, newSession) in client.auth.authStateChanges {
                await MainActor.run {
                    self.session = newSession
                    self.isRestoringSession = false
                    self.scheduleProfileAvatarLoad()
                    self.scheduleCompanyIdLoad()
                    self.scheduleOrganizationIdLoad()
                }
            }
        }
    }

    private func refreshSessionIfNeeded() async {
        defer { isRestoringSession = false }
        do {
            let s = try await client.auth.session
            await MainActor.run {
                self.session = s
                self.scheduleProfileAvatarLoad()
                self.scheduleCompanyIdLoad()
                self.scheduleOrganizationIdLoad()
            }
        } catch {
            await MainActor.run {
                self.session = client.auth.currentSession
                self.scheduleProfileAvatarLoad()
                self.scheduleCompanyIdLoad()
                self.scheduleOrganizationIdLoad()
            }
        }
    }

    /// Carga el `company_id` del usuario autenticado desde Supabase (`profiles.company_id`).
    private func scheduleCompanyIdLoad() {
        companyIdTask?.cancel()
        guard session != nil else {
            companyId = nil
            return
        }
        companyIdTask = Task {
            let cid = await VehiclesService.fetchMyCompanyId()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.companyId = cid
            }
        }
    }

    /// Carga el `organization_id` del usuario autenticado desde Supabase (`user_profiles.organization_id`).
    private func scheduleOrganizationIdLoad() {
        organizationIdTask?.cancel()
        guard session != nil else {
            organizationId = nil
            return
        }
        organizationIdTask = Task {
            let oid = await VehiclesService.fetchMyOrganizationId()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.organizationId = oid
            }
        }
    }

    private func scheduleProfileAvatarLoad() {
        profileAvatarTask?.cancel()
        guard let session else {
            profileAvatarImage = nil
            return
        }

        let user = session.user
        let userId = user.id
        let token = session.accessToken

        profileAvatarTask = Task { [client] in
            let ref = await UserProfileService.resolveAvatarRef(user: user, client: client)
            guard !Task.isCancelled else { return }
            let image = await UserProfileService.loadProfileAvatarImage(
                avatarRef: ref,
                userId: userId,
                client: client,
                accessToken: token
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.session?.user.id == userId else { return }
                self.profileAvatarImage = image
            }
        }
    }

    func signIn(email: String, password: String) async {
        clearAuthMessages()
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !password.isEmpty else {
            lastErrorMessage = "Introduce correo y contraseña."
            return
        }
        do {
            let s = try await client.auth.signIn(email: trimmed, password: password)
            session = s
            scheduleProfileAvatarLoad()
        } catch {
            lastErrorMessage = Self.mapAuthError(error)
        }
    }

    @discardableResult
    func signUp(email: String, password: String) async -> SignUpOutcome {
        clearAuthMessages()
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !password.isEmpty else {
            lastErrorMessage = "Introduce correo y contraseña."
            return .failed
        }
        do {
            let response = try await client.auth.signUp(email: trimmed, password: password)
            if let s = response.session {
                session = s
                scheduleProfileAvatarLoad()
                scheduleCompanyIdLoad()
                scheduleOrganizationIdLoad()
                return .signedIn
            }
            lastInfoMessage =
                "Cuenta creada. Revisa tu correo para confirmarla y luego inicia sesión."
            return .emailConfirmationRequired
        } catch {
            let mapped = Self.mapAuthError(error)
            if Self.isExistingAccountError(error) {
                lastInfoMessage = mapped
                return .existingAccount
            }
            lastErrorMessage = mapped
            return .failed
        }
    }

    func clearAuthMessages() {
        lastErrorMessage = nil
        lastInfoMessage = nil
    }

    /// Traduce errores habituales de Supabase Auth a mensajes claros en español.
    private static func mapAuthError(_ error: Error) -> String {
        let msg = error.localizedDescription.lowercased()
        if isExistingAccountError(error) {
            return "Ya existe una cuenta con este correo. Inicia sesión con tu contraseña."
        }
        if msg.contains("invalid login") || msg.contains("invalid credentials") {
            return "Correo o contraseña incorrectos."
        }
        if msg.contains("password") && (msg.contains("weak") || msg.contains("short") || msg.contains("least")) {
            return "La contraseña es demasiado débil. Usa al menos 6 caracteres."
        }
        if msg.contains("rate limit") || msg.contains("too many") || msg.contains("429") {
            return "Demasiados intentos. Espera un momento e inténtalo de nuevo."
        }
        if msg.contains("network") || msg.contains("internet") || msg.contains("offline")
            || msg.contains("timed out") || msg.contains("could not connect")
        {
            return "Sin conexión. Comprueba tu internet e inténtalo de nuevo."
        }
        if msg.contains("signup") && (msg.contains("disabled") || msg.contains("not allowed")) {
            return "El registro no está disponible en este momento."
        }
        if msg.contains("invalid email") || msg.contains("valid email") {
            return "Introduce un correo electrónico válido."
        }
        return error.localizedDescription
    }

    private static func isExistingAccountError(_ error: Error) -> Bool {
        let msg = error.localizedDescription.lowercased()
        return msg.contains("already registered")
            || msg.contains("user already")
            || msg.contains("user_already_exists")
    }

    /// Elimina la cuenta autenticada en Supabase Auth (`DELETE /auth/v1/user`) y cierra sesión local.
    func deleteCurrentAccount() async throws {
        clearAuthMessages()
        guard let s = session else {
            throw NSError(
                domain: "CarHub.Auth",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "No hay una sesión activa para eliminar."]
            )
        }
        var request = URLRequest(url: SupabaseClientProvider.supabaseURL.appending(path: "auth/v1/user"))
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseClientProvider.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(s.accessToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(
                domain: "CarHub.Auth",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Respuesta inesperada del servidor."]
            )
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw NSError(
                domain: "CarHub.Auth",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "No se pudo eliminar la cuenta. Inténtalo de nuevo."]
            )
        }
        try? await client.auth.signOut()
        profileAvatarTask?.cancel()
        companyIdTask?.cancel()
        organizationIdTask?.cancel()
        profileAvatarImage = nil
        companyId = nil
        organizationId = nil
        session = nil
    }

    func signOut() async {
        clearAuthMessages()
        do {
            try await client.auth.signOut()
            profileAvatarTask?.cancel()
            companyIdTask?.cancel()
            organizationIdTask?.cancel()
            profileAvatarImage = nil
            companyId = nil
            organizationId = nil
            session = nil
        } catch {
            lastErrorMessage = Self.mapAuthError(error)
        }
    }

    func resetPassword(email: String) async -> String? {
        clearAuthMessages()
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastErrorMessage = "Introduce tu correo."
            return nil
        }
        do {
            try await client.auth.resetPasswordForEmail(trimmed)
            return "Si existe una cuenta con ese correo, recibirás un enlace para restablecer la contraseña."
        } catch {
            lastErrorMessage = Self.mapAuthError(error)
            return nil
        }
    }
}
