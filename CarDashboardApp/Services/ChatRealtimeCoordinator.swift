import Foundation
import Supabase

/// Una sola capa de suscripciones Realtime de chat (inbox equipo).
/// Impide canales duplicados del mismo nombre lógico.
actor ChatRealtimeCoordinator {
    static let shared = ChatRealtimeCoordinator()

    private var directInboxChannel: RealtimeChannelV2?
    private var groupInboxChannel: RealtimeChannelV2?
    private var directListenTask: Task<Void, Never>?
    private var groupListenTask: Task<Void, Never>?
    private var activeUserId: UUID?

    private(set) var activeSubscriptionCount = 0

    func disconnectAll() async {
        directListenTask?.cancel()
        groupListenTask?.cancel()
        directListenTask = nil
        groupListenTask = nil
        if let directInboxChannel {
            await SupabaseClientProvider.shared.removeChannel(directInboxChannel)
        }
        if let groupInboxChannel {
            await SupabaseClientProvider.shared.removeChannel(groupInboxChannel)
        }
        directInboxChannel = nil
        groupInboxChannel = nil
        activeUserId = nil
        activeSubscriptionCount = 0
        ChatPerfLog.realtime("disconnected all")
    }

    /// Suscribe inbox DM + grupo para el usuario. Idempotente.
    func ensureTeamInboxSubscriptions(
        userId: UUID,
        onDirectInsert: @escaping @MainActor @Sendable (TeamDirectMessagesService.Row) -> Void,
        onGroupInsert: @escaping @MainActor @Sendable (TeamGroupMessagesService.Row) -> Void
    ) async {
        if activeUserId == userId, directInboxChannel != nil, groupInboxChannel != nil {
            ChatPerfLog.realtime("reuse existing subscriptions user=\(userId.uuidString.prefix(8)) count=\(activeSubscriptionCount)")
            return
        }

        await disconnectAll()
        activeUserId = userId

        let client = SupabaseClientProvider.shared

        // Direct inbox
        let dmChannel = client.channel("dm-inbox-global-\(userId.uuidString.lowercased())")
        let dmInserts = dmChannel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: TeamDirectMessagesService.tableName,
            filter: RealtimePostgresFilter.eq("recipient_id", value: userId)
        )
        do {
            try await dmChannel.subscribeWithError()
            directInboxChannel = dmChannel
            activeSubscriptionCount += 1
            ChatPerfLog.realtime("subscribed dm-inbox")
            directListenTask = Task {
                for await action in dmInserts {
                    guard !Task.isCancelled else { break }
                    guard let row = try? TeamDirectMessagesService.decodeInsert(action) else { continue }
                    guard row.senderId != userId else { continue }
                    await onDirectInsert(row)
                }
                await ChatRealtimeCoordinator.shared.clearDirectChannel()
            }
        } catch {
            ChatPerfLog.realtime("dm-inbox subscribe failed")
        }

        // Group inbox
        let groupChannel = client.channel("team-group-inbox-\(userId.uuidString.lowercased())")
        let groupInserts = groupChannel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: TeamGroupMessagesService.tableName
        )
        do {
            try await groupChannel.subscribeWithError()
            groupInboxChannel = groupChannel
            activeSubscriptionCount += 1
            ChatPerfLog.realtime("subscribed group-inbox")
            groupListenTask = Task {
                for await action in groupInserts {
                    guard !Task.isCancelled else { break }
                    guard let row = try? TeamGroupMessagesService.decodeInsert(action) else { continue }
                    guard row.senderId != userId else { continue }
                    await onGroupInsert(row)
                }
                await ChatRealtimeCoordinator.shared.clearGroupChannel()
            }
        } catch {
            ChatPerfLog.realtime("group-inbox subscribe failed")
        }

        ChatPerfLog.realtime("activeSubscriptions=\(activeSubscriptionCount)")
    }

    func clearDirectChannel() {
        directInboxChannel = nil
        if activeSubscriptionCount > 0 { activeSubscriptionCount -= 1 }
    }

    func clearGroupChannel() {
        groupInboxChannel = nil
        if activeSubscriptionCount > 0 { activeSubscriptionCount -= 1 }
    }
}
