import CryptoKit
import Foundation
import Security

/// Almacena solo el hash SHA256 del PIN (6 dígitos) en Keychain, **por usuario** (`userId` de Supabase).
enum AppPINKeychain {
    private static let service = "com.cardashboard.app.accessPin"
    /// Clave global antigua (una sola cuenta); se migra al primer acceso por usuario.
    private static let legacyAccount = "pin.sha256"

    private static func account(forUserId userId: UUID) -> String {
        "pin.sha256.\(userId.uuidString.lowercased())"
    }

    static func hashPIN(_ pin: String) -> Data {
        Data(SHA256.hash(data: Data(pin.utf8)))
    }

    static func saveHash(_ hash: Data, forUserId userId: UUID) {
        delete(forUserId: userId)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(forUserId: userId),
            kSecValueData as String: hash,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func loadHash(forUserId userId: UUID) -> Data? {
        if let data = loadHash(account: account(forUserId: userId)) {
            return data
        }
        // Migración: PIN guardado antes de la clave por usuario.
        if let legacy = loadHash(account: legacyAccount) {
            saveHash(legacy, forUserId: userId)
            deleteAccount(legacyAccount)
            return legacy
        }
        return nil
    }

    static func delete(forUserId userId: UUID) {
        deleteAccount(account(forUserId: userId))
    }

    private static func loadHash(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return nil }
        return data
    }

    private static func deleteAccount(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
