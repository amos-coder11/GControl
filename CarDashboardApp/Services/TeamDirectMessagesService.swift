import Foundation
import Supabase

/// Mensajes directos entre usuarios (`team_direct_messages` en Supabase).
enum TeamDirectMessagesService {
    static let tableName = "team_direct_messages"

    struct Row: Codable, Sendable, Identifiable, Equatable {
        let id: UUID
        let senderId: UUID
        let recipientId: UUID
        let body: String
        let createdAt: String
        let readAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case senderId = "sender_id"
            case recipientId = "recipient_id"
            case body
            case createdAt = "created_at"
            case readAt = "read_at"
        }
    }

    private struct NewRow: Encodable {
        let recipient_id: UUID
        let body: String
    }

    private struct MarkReadParams: Encodable {
        let p_peer: UUID
    }

    private static let jsonDecoder = PostgrestClient.Configuration.jsonDecoder

    static func fetchConversation(
        myUserId: UUID,
        peerUserId: UUID,
        client: SupabaseClient
    ) async throws -> [Row] {
        let a = myUserId.uuidString.lowercased()
        let b = peerUserId.uuidString.lowercased()
        let orFilter =
            "and(sender_id.eq.\(a),recipient_id.eq.\(b)),and(sender_id.eq.\(b),recipient_id.eq.\(a))"
        let rows: [Row] = try await client
            .from(tableName)
            .select()
            .or(orFilter)
            .order("created_at", ascending: true)
            .limit(500)
            .execute()
            .value
        return rows
    }

    static func send(
        recipientId: UUID,
        body: String,
        client: SupabaseClient
    ) async throws -> Row {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "TeamDirectMessages", code: 0, userInfo: [NSLocalizedDescriptionKey: "Vacío"])
        }
        if ContentModerationFilter.containsObjectionableContent(trimmed) {
            throw NSError(
                domain: "TeamDirectMessages",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "El mensaje incluye lenguaje no permitido."]
            )
        }
        let inserted: Row = try await client
            .from(tableName)
            .insert(NewRow(recipient_id: recipientId, body: trimmed))
            .select()
            .single()
            .execute()
            .value
        return inserted
    }

    static func markThreadRead(peerUserId: UUID, client: SupabaseClient) async throws {
        try await client
            .rpc("mark_team_direct_thread_read", params: MarkReadParams(p_peer: peerUserId))
            .execute()
    }

    static func decodeInsert(_ action: InsertAction) throws -> Row {
        try action.decodeRecord(as: Row.self, decoder: jsonDecoder)
    }

    static func decodeUpdate(_ action: UpdateAction) throws -> Row {
        try action.decodeRecord(as: Row.self, decoder: jsonDecoder)
    }

    static func parseCreatedAt(_ s: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: s)
    }
}
