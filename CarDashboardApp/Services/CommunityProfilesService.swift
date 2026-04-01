import Foundation
import Supabase

/// Perfiles públicos para Inicio: avatares, nombre y ubicación (mapa).
enum CommunityProfilesService {
    struct DirectoryRow: Decodable, Identifiable, Sendable, Equatable {
        /// PK de la fila en `user_profiles`.
        let id: UUID
        /// Mismo UUID que `auth.users.id` (sesión). Usar para filtros «yo / otros».
        let userId: UUID
        let fullName: String?
        let avatarUrl: String?
        let latitude: Double?
        let longitude: Double?
        /// ISO8601 desde Supabase (`location_updated_at`).
        let locationUpdatedAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case userId = "user_id"
            case fullName = "full_name"
            case avatarUrl = "avatar_url"
            case latitude
            case longitude
            case locationUpdatedAt = "location_updated_at"
        }

        var resolvedDisplayName: String {
            if let n = fullName?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { return n }
            return "Usuario"
        }

        var hasCoordinate: Bool {
            guard let lat = latitude, let lon = longitude else { return false }
            return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180
        }

        /// Fecha de la última posición guardada en servidor (si existe).
        var locationUpdatedDate: Date? {
            guard let s = locationUpdatedAt?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            let plain = ISO8601DateFormatter()
            if let d = plain.date(from: s) { return d }
            plain.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return plain.date(from: s)
        }
    }

    private struct LocationPayload: Encodable {
        let latitude: Double
        let longitude: Double
        let locationUpdatedAt: String

        enum CodingKeys: String, CodingKey {
            case latitude
            case longitude
            case locationUpdatedAt = "location_updated_at"
        }
    }

    private static let selectColumns = "id, user_id, avatar_url, full_name, latitude, longitude, location_updated_at"

    /// Listado para carrusel y mapa (requiere RLS que permita leer el directorio; ver `supabase/migrations`).
    static func fetchDirectory(client: SupabaseClient) async throws -> [DirectoryRow] {
        let rows: [DirectoryRow] = try await client
            .from(SupabaseClientProvider.profilesTableName)
            .select(selectColumns)
            .order("location_updated_at", ascending: false, nullsFirst: false)
            .limit(500)
            .execute()
            .value
        return rows
    }

    /// Sube la posición del usuario actual (silencioso si falla).
    static func pushMyLocation(
        userId: UUID,
        latitude: Double,
        longitude: Double,
        client: SupabaseClient
    ) async {
        let iso = ISO8601DateFormatter().string(from: Date())
        let payload = LocationPayload(latitude: latitude, longitude: longitude, locationUpdatedAt: iso)
        do {
            try await client
                .from(SupabaseClientProvider.profilesTableName)
                .update(payload)
                .eq("user_id", value: userId.uuidString.lowercased())
                .execute()
        } catch {
            // Columnas o políticas: revisar migración SQL en Supabase.
        }
    }
}
