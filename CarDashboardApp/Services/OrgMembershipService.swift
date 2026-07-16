import Foundation
import Supabase

/// Resolución de `organization_id` / `company_id` del usuario autenticado (endpoints Supabase).
enum OrgMembershipService {
    private struct UserProfileOrganizationRow: Decodable {
        let organization_id: UUID?
    }

    /// Organización del usuario (`user_profiles.organization_id` / tabla en `USER_PROFILES_TABLE`).
    static func fetchMyOrganizationId() async -> UUID? {
        do {
            let uid = try await SupabaseClientProvider.shared.auth.session.user.id
            let rows: [UserProfileOrganizationRow] = try await SupabaseClientProvider.shared
                .from(SupabaseClientProvider.profilesTableName)
                .select("organization_id")
                .eq("user_id", value: uid.uuidString.lowercased())
                .limit(1)
                .execute()
                .value
            return rows.first?.organization_id
        } catch {
            return nil
        }
    }

    /// `company_id` del usuario autenticado vía RPC `get_my_company_id`.
    static func fetchMyCompanyId() async -> UUID? {
        do {
            let result: String = try await SupabaseClientProvider.shared
                .rpc("get_my_company_id")
                .execute()
                .value
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\"")))
            return UUID(uuidString: trimmed)
        } catch {
            do {
                let data = try await SupabaseClientProvider.shared
                    .rpc("get_my_company_id")
                    .execute()
                    .data
                guard let raw = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\""))) else { return nil }
                if raw == "null" || raw.isEmpty { return nil }
                return UUID(uuidString: raw)
            } catch {
                return nil
            }
        }
    }
}
