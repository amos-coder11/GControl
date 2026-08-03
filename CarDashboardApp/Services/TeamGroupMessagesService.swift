import Foundation
import Supabase

/// Mensajes del grupo «Mi equipo» (`team_group_messages`).
enum TeamGroupMessagesService {
    static let tableName = "team_group_messages"

    struct Row: Codable, Sendable, Identifiable, Equatable {
        let id: UUID
        let senderId: UUID
        let body: String
        let createdAt: String

        enum CodingKeys: String, CodingKey {
            case id
            case senderId = "sender_id"
            case body
            case createdAt = "created_at"
        }
    }

    private struct NewRow: Encodable {
        let body: String
    }

    private struct BodyPatch: Encodable {
        let body: String
    }

    private static let jsonDecoder = PostgrestClient.Configuration.jsonDecoder

    static func fetchMessages(client: SupabaseClient) async throws -> [Row] {
        let rows: [Row] = try await client
            .from(tableName)
            .select()
            .order("created_at", ascending: true)
            .limit(500)
            .execute()
            .value
        return rows
    }

    static func send(body: String, client: SupabaseClient) async throws -> Row {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "TeamGroupMessages", code: 0, userInfo: [NSLocalizedDescriptionKey: "Vacío"])
        }
        if ContentModerationFilter.containsObjectionableContent(trimmed) {
            throw NSError(
                domain: "TeamGroupMessages",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "El mensaje incluye lenguaje no permitido."]
            )
        }
        let inserted: Row = try await client
            .from(tableName)
            .insert(NewRow(body: trimmed))
            .select()
            .single()
            .execute()
            .value
        return inserted
    }

    static func updateBody(id: UUID, body: String, client: SupabaseClient) async throws -> Row {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "TeamGroupMessages", code: 0, userInfo: [NSLocalizedDescriptionKey: "Vacío"])
        }
        if ContentModerationFilter.containsObjectionableContent(trimmed) {
            throw NSError(
                domain: "TeamGroupMessages",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "El mensaje incluye lenguaje no permitido."]
            )
        }
        return try await client
            .from(tableName)
            .update(BodyPatch(body: trimmed))
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    static func decodeInsert(_ action: InsertAction) throws -> Row {
        try action.decodeRecord(as: Row.self, decoder: jsonDecoder)
    }

    static func parseCreatedAt(_ s: String) -> Date? {
        TeamDirectMessagesService.parseCreatedAt(s)
    }
}
