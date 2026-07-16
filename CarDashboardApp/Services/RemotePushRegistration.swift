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
                #if DEBUG
                print("[Drflow APNs] Permiso de notificaciones denegado: no habrá push hasta que lo actives en Ajustes.")
                #endif
                return
            }
            await WorkdayNotificationService.rescheduleAll()
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            #if DEBUG
            print("Permiso de notificaciones: \(error)")
            #endif
        }
    }

    /// Llamar cuando APNs devuelve el token (desde `AppDelegate`).
    static func storeDeviceTokenFromAPNs(_ data: Data) {
        let hex = data.map { String(format: "%02.2hhx", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: pendingTokenKey)
        #if DEBUG
        let prefix = hex.prefix(12)
        print("[Drflow APNs] Token recibido de Apple (hex \(prefix)…, \(hex.count) chars). Subiendo a Supabase si hay sesión.")
        #endif
        Task {
            await syncPendingTokenToSupabase()
        }
    }

    /// Tras iniciar sesión, reintenta subir el token pendiente.
    static func syncPendingTokenToSupabase(client: SupabaseClient = SupabaseClientProvider.shared) async {
        guard let hex = UserDefaults.standard.string(forKey: pendingTokenKey), !hex.isEmpty else { return }
        guard let uid = client.auth.currentSession?.user.id else {
            #if DEBUG
            print("[Drflow APNs] Hay token pero no hay sesión: inicia sesión para guardarlo en user_apns_devices.")
            #endif
            return
        }

        struct Row: Encodable {
            let user_id: UUID
            let device_token: String
        }

        do {
            try await client
                .from("user_apns_devices")
                .upsert(Row(user_id: uid, device_token: hex), onConflict: "user_id,device_token")
                .execute()
            #if DEBUG
            print("[Drflow APNs] OK: token guardado en Supabase (user_apns_devices) para usuario \(uid.uuidString.prefix(8))…")
            #endif
        } catch {
            #if DEBUG
            print("[Drflow APNs] Error al guardar token: \(error)")
            #endif
        }
    }
}
