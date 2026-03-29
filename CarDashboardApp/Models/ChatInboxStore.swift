import Foundation
import SwiftUI

/// Estado compartido de la bandeja de chats: lista, overrides y total para el badge de la pestaña.
final class ChatInboxStore: ObservableObject {
    @Published var liveThreads: [ChatThread] = Array(ChatThread.samples)
    @Published private(set) var pinOverride: [UUID: Bool] = [:]
    @Published private(set) var unreadOverride: [UUID: Int] = [:]

    /// Suma de mensajes sin leer / sin responder en todos los hilos visibles.
    var totalUnansweredMessageCount: Int {
        liveThreads.reduce(0) { sum, thread in
            let u = unreadOverride[thread.id] ?? thread.unread
            return sum + max(0, u ?? 0)
        }
    }

    func effectivePinned(_ thread: ChatThread) -> Bool {
        pinOverride[thread.id] ?? thread.isPinned
    }

    func effectiveUnread(_ thread: ChatThread) -> Int? {
        if let o = unreadOverride[thread.id] { return o }
        return thread.unread
    }

    func markThreadAsRead(_ id: UUID) {
        var copy = unreadOverride
        copy[id] = 0
        unreadOverride = copy
    }

    func archiveThread(_ thread: ChatThread) {
        liveThreads.removeAll { $0.id == thread.id }
        var p = pinOverride
        p.removeValue(forKey: thread.id)
        pinOverride = p
        var u = unreadOverride
        u.removeValue(forKey: thread.id)
        unreadOverride = u
    }

    func deleteThread(_ thread: ChatThread) {
        archiveThread(thread)
    }

    func markUnread(_ thread: ChatThread) {
        let next = max(thread.unread ?? 1, unreadOverride[thread.id] ?? 1, 1)
        var copy = unreadOverride
        copy[thread.id] = next
        unreadOverride = copy
    }

    func togglePin(_ thread: ChatThread) {
        let current = pinOverride[thread.id] ?? thread.isPinned
        var copy = pinOverride
        copy[thread.id] = !current
        pinOverride = copy
    }
}
