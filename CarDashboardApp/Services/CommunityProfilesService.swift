import Foundation
import Supabase

/// Perfiles públicos para Inicio: avatares, nombre y ubicación (mapa).
enum CommunityProfilesService {
    struct DirectoryRow: Decodable, Identifiable, Sendable {
        let id: UUID
        let fullName: String?
        let avatarUrl: String?
        let latitude: Double?
        let longitude: Double?

        enum CodingKeys: String, CodingKey {
            case id
            case fullName = "full_name"
            case avatarUrl = "avatar_url"
            case latitude
            case longitude
        }

        var resolvedDisplayName: String {
            if let n = fullName?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { return n }
            return "Usuario"
        }

        var hasCoordinate: Bool {
            guard let lat = latitude, let lon = longitude else { return false }
            return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180
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

    private static let selectColumns = "id, avatar_url, full_name, latitude, longitude"

    /// Listado para carrusel y mapa (respeta RLS).
    static func fetchDirectory(client: SupabaseClient) async throws -> [DirectoryRow] {
        let rows: [DirectoryRow] = try await client
            .from(SupabaseClientProvider.profilesTableName)
            .select(selectColumns)
            .order("id", ascending: true)
            .limit(80)
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
                .eq("id", value: userId.uuidString.lowercased())
                .execute()
        } catch {
            // Columnas o políticas: revisar migración SQL en Supabase.
        }
    }
}
