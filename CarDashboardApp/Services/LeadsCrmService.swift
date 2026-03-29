import Foundation
import Supabase

/// Lectura de `public.leads_crm` (misma tabla que `LeadsCrmRepository` en Flutter).
enum LeadsCrmService {
    static let tableName = "leads_crm"
    static let defaultLimit = 500

    static func fetchAll(
        limit: Int = defaultLimit,
        client: SupabaseClient = SupabaseClientProvider.shared
    ) async throws -> [LeadCrm] {
        let rows: [JSONObject] = try await fetchRowsWithFallback(limit: limit, client: client)
        return rows.compactMap { LeadCrm(json: $0) }
    }

    /// Intenta `order(created_at)` como Flutter; si falla, `id`; si falla, select plano.
    private static func fetchRowsWithFallback(limit: Int, client: SupabaseClient) async throws -> [JSONObject] {
        do {
            return try await client
                .from(tableName)
                .select()
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
        } catch {
            do {
                return try await client
                    .from(tableName)
                    .select()
                    .order("id", ascending: false)
                    .limit(limit)
                    .execute()
                    .value
            } catch {
                return try await client
                    .from(tableName)
                    .select()
                    .limit(limit)
                    .execute()
                    .value
            }
        }
    }
}
