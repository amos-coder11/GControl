import Foundation
import LocalAuthentication
import SwiftUI

/// Bloqueo local: Face ID / Touch ID con fallback al código del dispositivo, más PIN de 6 dígitos de la app (por usuario).
@MainActor
final class AppLockManager: ObservableObject {
    @Published var isUnlocked = false
    @Published var isAuthenticating = false
    @Published var authError: String?
    @Published private(set) var hasPINConfigured = false

    /// Usuario con sesión activa; el PIN en Keychain está ligado a este id.
    private(set) var activeUserId: UUID?

    init() {
        activeUserId = nil
        hasPINConfigured = false
    }

    /// Llama al iniciar o cambiar sesión.
    func setActiveUser(_ userId: UUID?) {
        authError = nil
        guard userId != nil else {
            activeUserId = nil
            hasPINConfigured = false
            isUnlocked = false
            return
        }
        activeUserId = userId
        hasPINConfigured = true
        isUnlocked = true
    }

    func refreshPINState() {
        guard let uid = activeUserId else {
            hasPINConfigured = false
            return
        }
        hasPINConfigured = AppPINKeychain.loadHash(forUserId: uid) != nil
    }

    var biometryType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    var biometryName: String {
        switch biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        @unknown default: return "Biometría"
        }
    }

    /// Biometría + código del dispositivo si hace falta (recomendado por Apple).
    func authenticateWithBiometry() {
        let context = LAContext()
        context.localizedFallbackTitle = "Usar código"

        isAuthenticating = true
        authError = nil

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isAuthenticating = false
            if let la = error as? LAError, la.code == .biometryNotAvailable {
                authError = nil
            } else {
                authError = error?.localizedDescription
            }
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Verifica tu identidad para acceder al panel"
        ) { [weak self] success, authenticationError in
            Task { @MainActor in
                guard let self else { return }
                self.isAuthenticating = false
                if success {
                    self.isUnlocked = true
                    self.authError = nil
                } else if let err = authenticationError as? LAError {
                    switch err.code {
                    case .userCancel, .systemCancel, .appCancel, .userFallback:
                        self.authError = nil
                    case .biometryNotAvailable:
                        self.authError = nil
                    default:
                        self.authError = err.localizedDescription
                    }
                } else {
                    self.authError = authenticationError?.localizedDescription
                }
            }
        }
    }

    func submitPIN(_ pin: String) {
        guard let uid = activeUserId else {
            authError = "Sesión no disponible."
            return
        }
        guard pin.count == 6, pin.allSatisfy(\.isNumber) else { return }
        guard let stored = AppPINKeychain.loadHash(forUserId: uid) else {
            authError = "No hay PIN guardado para esta cuenta."
            return
        }
        let candidate = AppPINKeychain.hashPIN(pin)
        if candidate == stored {
            isUnlocked = true
            authError = nil
        } else {
            authError = "PIN incorrecto"
        }
    }

    func savePINAndUnlock(_ pin: String, userId: UUID) {
        guard pin.count == 6, pin.allSatisfy(\.isNumber) else { return }
        let hash = AppPINKeychain.hashPIN(pin)
        AppPINKeychain.saveHash(hash, forUserId: userId)
        activeUserId = userId
        hasPINConfigured = true
        isUnlocked = true
        authError = nil
    }

    func lock() {}

    /// Solo cuando el usuario indica que olvidó el PIN: borra el PIN **de esa cuenta** y debe volver a crearlo al entrar.
    func clearPINForUser(_ userId: UUID) {
        AppPINKeychain.delete(forUserId: userId)
        if activeUserId == userId {
            hasPINConfigured = false
            isUnlocked = false
        }
        authError = nil
    }
}
