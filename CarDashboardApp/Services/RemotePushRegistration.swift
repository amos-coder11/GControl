import Foundation
import Supabase
import UIKit
import UserNotifications

/// Registro de APNs y sincronización del token con Supabase (`user_apns_devices`).
enum RemotePushRegistration {
    private static let pendingTokenKey = "Drflow.pendingAPNsTokenHex"

    /// Solicita permiso de alertas y registra el dispositivo en APNs (token llega al `AppDelegate`).
    @MainActor
    static func requestAuthorizationAndRegister() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else {
                pushLog("Permiso de notificaciones denegado.")
                return
            }
            await WorkdayNotificationService.rescheduleAll()
            registerForRemoteNotifications()
        } catch {
            pushLog("Error pidiendo permiso: \(error.localizedDescription)")
        }
    }

    /// Si ya hay permiso, vuelve a registrar el token (p. ej. al volver a primer plano).
    @MainActor
    static func refreshIfAuthorized() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            registerForRemoteNotifications()
            await syncPendingTokenToSupabase()
        default:
            break
        }
    }

    @MainActor
    private static func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Llamar cuando APNs devuelve el token (desde `AppDelegate`).
    static func storeDeviceTokenFromAPNs(_ data: Data) {
        let hex = data.map { String(format: "%02.2hhx", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: pendingTokenKey)
        pushLog("Token APNs recibido (\(hex.prefix(12))…, \(hex.count) chars)")
        Task {
            await syncPendingTokenToSupabase()
        }
    }

    /// Tras iniciar sesión, reintenta subir el token pendiente.
    static func syncPendingTokenToSupabase(client: SupabaseClient = SupabaseClientProvider.shared) async {
        guard let hex = UserDefaults.standard.string(forKey: pendingTokenKey), !hex.isEmpty else {
            pushLog("Sin token APNs local todavía (¿simulador o permiso denegado?).")
            return
        }
        guard let uid = client.auth.currentSession?.user.id else {
            pushLog("Token APNs pendiente pero sin sesión Supabase.")
            return
        }

        struct Row: Encodable {
            let user_id: UUID
            let device_token: String
            let updated_at: String
        }

        let iso = ISO8601DateFormatter().string(from: Date())
        do {
            try await client
                .from("user_apns_devices")
                .upsert(
                    Row(user_id: uid, device_token: hex, updated_at: iso),
                    onConflict: "user_id,device_token"
                )
                .execute()
            pushLog("Token guardado en Supabase para \(uid.uuidString.prefix(8))…")
        } catch {
            pushLog("Error guardando token en Supabase: \(error.localizedDescription)")
        }
    }

    private static func pushLog(_ message: String) {
        #if DEBUG
        print("[GControl APNs] \(message)")
        #endif
    }
}
