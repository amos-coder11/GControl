import Foundation
import Supabase

/// Credenciales Supabase del proyecto Groo.
enum SupabaseClientProvider {
    static let supabaseURL = URL(string: "https://fwdfhbgcurimqufbwkux.supabase.co")!
    static let anonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ3ZGZoYmdjdXJpbXF1ZmJ3a3V4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI2MzkzNzUsImV4cCI6MjA4ODIxNTM3NX0.paCpihrCLZGO2cZ8QwG81SPJeo6wsRmMyUhfoguk4IA"

    static let shared: SupabaseClient = {
        SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
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
                auth: .init(
                    storageKey: "sb-\(ref)-auth-token-catalog-anon",
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }()

    /// Tabla pública de perfiles (columna típica `avatar_url`).
    static var profilesTableName: String {
        let fromInfoPlist = (Bundle.main.object(forInfoDictionaryKey: "USER_PROFILES_TABLE") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let v = fromInfoPlist, !v.isEmpty else { return "profiles" }
        return v
    }

    /// Bucket privado para notas de voz en mensajes directos de equipo.
    static let teamDirectVoiceBucket = "team_direct_voice"

    /// Bucket Storage para fotos de perfil (ruta relativa guardada en `avatar_url`).
    static var userAvatarBucket: String {
        let fromInfoPlist = (Bundle.main.object(forInfoDictionaryKey: "USER_AVATAR_BUCKET") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let v = fromInfoPlist, !v.isEmpty else { return "avatars" }
        return v
    }

    /// URL pública de objeto: `{supabaseURL}/storage/v1/object/public/{bucket}/{path}`.
    static func publicStorageObjectURL(bucket: String? = nil, path relativePath: String) -> String {
        let b = (bucket ?? userAvatarBucket).trimmingCharacters(in: .whitespacesAndNewlines)
        let clean = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encoded = clean.split(separator: "/").map(String.init).map { seg -> String in
            seg.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? seg
        }.joined(separator: "/")
        let base = supabaseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(base)/storage/v1/object/public/\(b)/\(encoded)"
    }
}
