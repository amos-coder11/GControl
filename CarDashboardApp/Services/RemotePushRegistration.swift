import Foundation
import Supabase
import UIKit
import UserNotifications

/// Registro de APNs y sincronización del token con Supabase (`user_apns_devices`).
enum RemotePushRegistration {
    private static let pendingTokenKey = "CarHub.pendingAPNsTokenHex"

    /// Solicita permiso de alertas y registra el dispositivo en APNs (token llega al `AppDelegate`).
    @MainActor
    static func requestAuthorizationAndRegister() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return }
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
        Task {
            await syncPendingTokenToSupabase()
        }
    }

    /// Tras iniciar sesión, reintenta subir el token pendiente.
    static func syncPendingTokenToSupabase(client: SupabaseClient = SupabaseClientProvider.shared) async {
        guard let hex = UserDefaults.standard.string(forKey: pendingTokenKey), !hex.isEmpty else { return }
        guard let uid = client.auth.currentSession?.user.id else { return }

        struct Row: Encodable {
            let user_id: UUID
            let device_token: String
        }

        do {
            try await client
                .from("user_apns_devices")
                .upsert(Row(user_id: uid, device_token: hex), onConflict: "user_id,device_token")
                .execute()
        } catch {
            #if DEBUG
            print("user_apns_devices upsert: \(error)")
            #endif
        }
    }
}
