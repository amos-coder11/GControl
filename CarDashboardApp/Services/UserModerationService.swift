import Foundation
import Supabase

/// Denuncias, bloqueos y aceptación de términos UGC en Supabase.
enum UserModerationService {
    static let termsTable = "user_terms_acceptance"
    static let blockedTable = "blocked_users"
    static let reportsTable = "content_reports"

    enum ContentType: String {
        case teamDirectMessage = "team_direct_message"
        case teamGroupMessage = "team_group_message"
        case userProfile = "user_profile"
    }

    struct TermsRow: Codable {
        let userId: UUID
        let termsVersion: String
        let acceptedAt: String

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case termsVersion = "terms_version"
            case acceptedAt = "accepted_at"
        }
    }

    struct BlockedRow: Codable, Identifiable {
        let id: UUID
        let blockerId: UUID
        let blockedId: UUID
        let createdAt: String

        enum CodingKeys: String, CodingKey {
            case id
            case blockerId = "blocker_id"
            case blockedId = "blocked_id"
            case createdAt = "created_at"
        }
    }

    private struct NewTermsRow: Encodable {
        let user_id: UUID
        let terms_version: String
    }

    private struct NewBlockedRow: Encodable {
        let blocked_id: UUID
    }

    private struct NewReportRow: Encodable {
        let reported_user_id: UUID
        let content_type: String
        let content_id: UUID?
        let content_preview: String?
        let reason: String
    }

    static func fetchTermsAcceptance(userId: UUID, client: SupabaseClient) async throws -> TermsRow? {
        let rows: [TermsRow] = try await client
            .from(termsTable)
            .select()
            .eq("user_id", value: userId.uuidString.lowercased())
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    static func acceptTerms(userId: UUID, client: SupabaseClient) async throws {
        let payload = NewTermsRow(
            user_id: userId,
            terms_version: ContentModerationFilter.currentTermsVersion
        )
        try await client
            .from(termsTable)
            .upsert(payload, onConflict: "user_id")
            .execute()
    }

    static func fetchBlockedUserIds(for blockerId: UUID, client: SupabaseClient) async throws -> Set<UUID> {
        let rows: [BlockedRow] = try await client
            .from(blockedTable)
            .select()
            .eq("blocker_id", value: blockerId.uuidString.lowercased())
            .execute()
            .value
        return Set(rows.map(\.blockedId))
    }

    static func fetchBlockedUsers(for blockerId: UUID, client: SupabaseClient) async throws -> [BlockedRow] {
        try await client
            .from(blockedTable)
            .select()
            .eq("blocker_id", value: blockerId.uuidString.lowercased())
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    @discardableResult
    static func blockUser(
        blockedId: UUID,
        client: SupabaseClient
    ) async throws -> BlockedRow {
        let inserted: BlockedRow = try await client
            .from(blockedTable)
            .insert(NewBlockedRow(blocked_id: blockedId))
            .select()
            .single()
            .execute()
            .value
        return inserted
    }

    static func unblockUser(blockedId: UUID, client: SupabaseClient) async throws {
        try await client
            .from(blockedTable)
            .delete()
            .eq("blocked_id", value: blockedId.uuidString.lowercased())
            .execute()
    }

    static func submitReport(
        reportedUserId: UUID,
        contentType: ContentType,
        contentId: UUID?,
        contentPreview: String?,
        reason: String,
        client: SupabaseClient
    ) async throws {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else {
            throw NSError(
                domain: "UserModeration",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Indica un motivo para la denuncia."]
            )
        }
        let preview: String? = {
            guard let contentPreview else { return nil }
            let trimmed = contentPreview.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return String(trimmed.prefix(500))
        }()
        try await client
            .from(reportsTable)
            .insert(
                NewReportRow(
                    reported_user_id: reportedUserId,
                    content_type: contentType.rawValue,
                    content_id: contentId,
                    content_preview: preview,
                    reason: trimmedReason
                )
            )
            .execute()
    }
}
