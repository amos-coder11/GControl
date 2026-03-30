import Foundation
import LocalAuthentication
import SwiftUI

/// Bloqueo local: Face ID / Touch ID con fallback al código del dispositivo, más PIN de 6 dígitos de la app.
@MainActor
final class AppLockManager: ObservableObject {
    @Published var isUnlocked = false
    @Published var isAuthenticating = false
    @Published var authError: String?
    @Published private(set) var hasPINConfigured = false

    init() {
        hasPINConfigured = AppPINKeychain.loadHash() != nil
    }

    func refreshPINState() {
        hasPINConfigured = AppPINKeychain.loadHash() != nil
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
            authError = error?.localizedDescription ?? "Autenticación no disponible en este dispositivo."
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
        guard pin.count == 6, pin.allSatisfy(\.isNumber) else { return }
        guard let stored = AppPINKeychain.loadHash() else {
            authError = "No hay PIN guardado."
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

    func savePINAndUnlock(_ pin: String) {
        guard pin.count == 6, pin.allSatisfy(\.isNumber) else { return }
        let hash = AppPINKeychain.hashPIN(pin)
        AppPINKeychain.saveHash(hash)
        hasPINConfigured = true
        isUnlocked = true
        authError = nil
    }

    func lock() {
        isUnlocked = false
    }

    /// Tras cerrar sesión o “olvidé el PIN”.
    func clearPIN() {
        AppPINKeychain.delete()
        hasPINConfigured = false
        isUnlocked = false
        authError = nil
    }
}
