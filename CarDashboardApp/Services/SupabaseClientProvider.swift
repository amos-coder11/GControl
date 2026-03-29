import Foundation
import Supabase

/// Credenciales del proyecto (misma base que `carhubapp` / `app.env`).
enum SupabaseClientProvider {
    static let supabaseURL = URL(string: "https://fwdfhbgcurimqufbwkux.supabase.co")!
    static let anonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ3ZGZoYmdjdXJpbXF1ZmJ3a3V4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI2MzkzNzUsImV4cCI6MjA4ODIxNTM3NX0.paCpihrCLZGO2cZ8QwG81SPJeo6wsRmMyUhfoguk4IA"

    static let shared: SupabaseClient = {
        SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: anonKey
        )
    }()

    /// Bucket donde la app espera URLs/descargas de miniaturas públicas.
    static let publicVehiclesBucket = "vehicles"

    /// Bucket principal de medios de vehículos (privado en la app Flutter).
    static var vehicleMediaBucket: String {
        let fromInfoPlist = (Bundle.main.object(forInfoDictionaryKey: "VEHICLE_MEDIA_BUCKET") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let v = fromInfoPlist, !v.isEmpty else { return "vehicle-media" }
        return v
    }
}
