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

    /// Cliente sin compartir almacén de sesión con `shared`: las peticiones REST van solo con la clave `anon`
    /// (no adjuntan el JWT del usuario). Útil para combinar con `shared` cuando RLS devuelve filas distintas
    /// por rol (`anon` vs `authenticated`).
    static let catalogAnon: SupabaseClient = {
        let ref = supabaseURL.host!.split(separator: ".")[0]
        return SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(
                auth: .init(storageKey: "sb-\(ref)-auth-token-catalog-anon")
            )
        )
    }()

    /// Tabla PostgREST del inventario (por si en tu proyecto no se llama `vehicles`).
    static var vehiclesTableName: String {
        let fromInfoPlist = (Bundle.main.object(forInfoDictionaryKey: "VEHICLES_TABLE") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let v = fromInfoPlist, !v.isEmpty else { return "vehicles" }
        return v
    }

    /// Nombre de la RPC en Supabase (`supabase/migrations/20260330140000_marketplace_vehicles_rpc.sql`).
    static let marketplaceVehiclesRPCName = "marketplace_vehicles_page"

    /// Si es `false` (Info.plist `USE_MARKETPLACE_VEHICLES_RPC`), se omite la RPC y solo se usa el listado por tabla.
    static var prefersMarketplaceVehiclesRPC: Bool {
        if let b = Bundle.main.object(forInfoDictionaryKey: "USE_MARKETPLACE_VEHICLES_RPC") as? Bool { return b }
        return true
    }

    /// Bucket donde la app espera URLs/descargas de miniaturas públicas.
    static let publicVehiclesBucket = "vehicles"

    /// Bucket principal de medios de vehículos (privado en la app Flutter).
    static var vehicleMediaBucket: String {
        let fromInfoPlist = (Bundle.main.object(forInfoDictionaryKey: "VEHICLE_MEDIA_BUCKET") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let v = fromInfoPlist, !v.isEmpty else { return "vehicle-media" }
        return v
    }

    /// Tabla pública de perfiles (columna típica `avatar_url`).
    static var profilesTableName: String {
        let fromInfoPlist = (Bundle.main.object(forInfoDictionaryKey: "USER_PROFILES_TABLE") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let v = fromInfoPlist, !v.isEmpty else { return "profiles" }
        return v
    }

    /// Bucket Storage para fotos de perfil (ruta relativa guardada en `avatar_url`).
    static var userAvatarBucket: String {
        let fromInfoPlist = (Bundle.main.object(forInfoDictionaryKey: "USER_AVATAR_BUCKET") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let v = fromInfoPlist, !v.isEmpty else { return "avatars" }
        return v
    }

    /// URL pública de objeto: `{supabaseURL}/storage/v1/object/public/{bucket}/{path}` (p. ej. `vehicle-media/{user_id}/{vehicle_id}/001.jpg`).
    static func publicStorageObjectURL(bucket: String? = nil, path relativePath: String) -> String {
        let b = (bucket ?? vehicleMediaBucket).trimmingCharacters(in: .whitespacesAndNewlines)
        let clean = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encoded = clean.split(separator: "/").map(String.init).map { seg -> String in
            seg.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? seg
        }.joined(separator: "/")
        let base = supabaseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(base)/storage/v1/object/public/\(b)/\(encoded)"
    }
}
