import Foundation
import SwiftUI

// MARK: - Tarea enviada por el coordinador IA (el compañero acepta y sube pruebas paso a paso)

struct CoordinatorTaskStep: Identifiable, Equatable {
    let id: UUID
    var instruction: String
    var proofImageData: Data?
    var verified: Bool

    init(id: UUID = UUID(), instruction: String, proofImageData: Data? = nil, verified: Bool = false) {
        self.id = id
        self.instruction = instruction
        self.proofImageData = proofImageData
        self.verified = verified
    }
}

struct CoordinatorOutboundTask: Identifiable, Equatable {
    let id: UUID
    let peerUserId: UUID
    var title: String
    var body: String
    /// `nil` hasta que el compañero pulse «Aceptar tarea».
    var acceptedAt: Date?
    var steps: [CoordinatorTaskStep]

    var isComplete: Bool {
        !steps.isEmpty && steps.allSatisfy(\.verified)
    }

    init(
        id: UUID = UUID(),
        peerUserId: UUID,
        title: String,
        body: String,
        acceptedAt: Date? = nil,
        steps: [CoordinatorTaskStep]
    ) {
        self.id = id
        self.peerUserId = peerUserId
        self.title = title
        self.body = body
        self.acceptedAt = acceptedAt
        self.steps = steps
    }
}

/// Estado compartido de la bandeja de chats: lista, overrides y total para el badge de la pestaña.
final class ChatInboxStore: ObservableObject {
    @Published var liveThreads: [ChatThread] = Array(ChatThread.samples)
    /// Grupo «Mi equipo» y DMs del directorio (se actualizan con el listado de comunidad).
    @Published var teamGroupChatThread: ChatThread?
    @Published var teamDirectChatThreads: [ChatThread] = []
    /// Texto mostrado en la fila del chat de cada compañero tras un envío desde IA.
    @Published private(set) var teamCoordinatorPeerPreview: [UUID: String] = [:]
    /// Tareas con pruebas por pasos (clave = `userId` del compañero destinatario).
    @Published private(set) var coordinatorTasksByPeer: [UUID: [CoordinatorOutboundTask]] = [:]
    /// Se incrementa al mutar tareas para forzar scroll al final del hilo.
    @Published private(set) var coordinatorTimelineTick: Int = 0

    /// `userId` del compañero si la vista de conversación DM equipo está visible.
    @Published var activeTeamDirectPeerId: UUID?
    /// El chat grupal «Mi equipo» está en primer plano.
    @Published var activeTeamGroupChatOpen: Bool = false
    /// Vista previa / hora por `peerUserId` para hilos `teamDirect` (mensajería real).
    @Published private(set) var teamDirectPreviewBody: [UUID: String] = [:]
    @Published private(set) var teamDirectPreviewTime: [UUID: String] = [:]
    /// Orden de lista: conversación con el último mensaje más reciente primero.
    @Published private(set) var teamDirectLastActivityAt: [UUID: Date] = [:]
    /// Vista previa del grupo «Mi equipo» (un solo hilo).
    @Published private(set) var teamGroupPreviewBody: String?
    @Published private(set) var teamGroupPreviewTime: String?

    private var lastTeamDirectorySnapshot: [CommunityProfilesService.DirectoryRow] = []
    private var lastTeamDirectoryUserId: UUID?
    @Published private(set) var pinOverride: [UUID: Bool] = [:]
    @Published private(set) var unreadOverride: [UUID: Int] = [:]

    private func bumpCoordinatorTimeline() {
        coordinatorTimelineTick += 1
    }

    func coordinatorTasks(forPeer peerUserId: UUID) -> [CoordinatorOutboundTask] {
        coordinatorTasksByPeer[peerUserId] ?? []
    }

    func appendCoordinatorTask(peerUserId: UUID, title: String, body: String, stepInstructions: [String]) {
        let steps = stepInstructions.map { CoordinatorTaskStep(instruction: $0) }
        let task = CoordinatorOutboundTask(peerUserId: peerUserId, title: title, body: body, steps: steps)
        var arr = coordinatorTasksByPeer[peerUserId] ?? []
        arr.append(task)
        coordinatorTasksByPeer[peerUserId] = arr
        bumpCoordinatorTimeline()
    }

    func acceptCoordinatorTask(peerUserId: UUID, taskId: UUID) {
        guard var arr = coordinatorTasksByPeer[peerUserId],
              let i = arr.firstIndex(where: { $0.id == taskId })
        else { return }
        arr[i].acceptedAt = Date()
        coordinatorTasksByPeer[peerUserId] = arr
        bumpCoordinatorTimeline()
    }

    func setCoordinatorStepProof(peerUserId: UUID, taskId: UUID, stepId: UUID, imageData: Data) {
        guard var arr = coordinatorTasksByPeer[peerUserId],
              let ti = arr.firstIndex(where: { $0.id == taskId })
        else { return }
        var task = arr[ti]
        guard let si = task.steps.firstIndex(where: { $0.id == stepId }) else { return }
        task.steps[si].proofImageData = imageData
        arr[ti] = task
        coordinatorTasksByPeer[peerUserId] = arr
        bumpCoordinatorTimeline()
    }

    func verifyCoordinatorStep(peerUserId: UUID, taskId: UUID, stepId: UUID) {
        guard var arr = coordinatorTasksByPeer[peerUserId],
              let ti = arr.firstIndex(where: { $0.id == taskId })
        else { return }
        var task = arr[ti]
        guard let si = task.steps.firstIndex(where: { $0.id == stepId }) else { return }
        guard task.steps[si].proofImageData != nil else { return }
        task.steps[si].verified = true
        arr[ti] = task
        coordinatorTasksByPeer[peerUserId] = arr
        bumpCoordinatorTimeline()
    }

    private func unreadContribution(for thread: ChatThread) -> Int {
        let u = unreadOverride[thread.id] ?? thread.unread
        return max(0, u ?? 0)
    }

    /// Suma de mensajes sin leer / sin responder en todos los hilos visibles.
    var totalUnansweredMessageCount: Int {
        let leadSum = liveThreads.reduce(0) { $0 + unreadContribution(for: $1) }
        let teamSum = ([teamGroupChatThread].compactMap { $0 } + teamDirectChatThreads)
            .reduce(0) { $0 + unreadContribution(for: $1) }
        return leadSum + teamSum
    }

    /// Sincroniza hilos de equipo desde el directorio (grupo + un DM por compañero, excluyéndote).
    func syncTeamThreads(from directory: [CommunityProfilesService.DirectoryRow], currentUserId: UUID?) {
        lastTeamDirectorySnapshot = directory
        lastTeamDirectoryUserId = currentUserId
        if directory.isEmpty {
            teamGroupChatThread = nil
            teamDirectChatThreads = []
            return
        }
        var tg = ChatThread.makeTeamGroup(memberCount: directory.count)
        if let pb = teamGroupPreviewBody, let pt = teamGroupPreviewTime {
            tg = tg.withGroupChatPreview(pb, time: pt)
        }
        teamGroupChatThread = tg
        let peers = directory
            .filter { $0.userId != currentUserId }
            .sorted { a, b in
                let da = teamDirectLastActivityAt[a.userId] ?? .distantPast
                let db = teamDirectLastActivityAt[b.userId] ?? .distantPast
                if da != db { return da > db }
                return a.resolvedDisplayName.localizedCaseInsensitiveCompare(b.resolvedDisplayName) == .orderedAscending
            }
        teamDirectChatThreads = peers.map { row in
            let base = ChatThread.makeTeamDirect(from: row)
            if let line = teamCoordinatorPeerPreview[row.userId] {
                return base.withCoordinatorOutboundPreview(line)
            }
            if let body = teamDirectPreviewBody[row.userId], let t = teamDirectPreviewTime[row.userId] {
                return base.withDirectMessagePreview(body, time: t)
            }
            return base
        }
    }

    func applyTeamDirectOutgoing(toPeer peerId: UUID, body: String, date: Date) {
        var b = teamDirectPreviewBody
        b[peerId] = body
        teamDirectPreviewBody = b
        var t = teamDirectPreviewTime
        t[peerId] = Self.formatShortListTime(date)
        teamDirectPreviewTime = t
        var act = teamDirectLastActivityAt
        act[peerId] = date
        teamDirectLastActivityAt = act
        refreshTeamThreadsFromSnapshot()
    }

    /// Llega un mensaje dirigido al usuario actual (p. ej. Realtime bandeja).
    func applyTeamDirectIncoming(fromPeer peerId: UUID, body: String, date: Date) {
        var b = teamDirectPreviewBody
        b[peerId] = body
        teamDirectPreviewBody = b
        var t = teamDirectPreviewTime
        t[peerId] = Self.formatShortListTime(date)
        teamDirectPreviewTime = t
        var act = teamDirectLastActivityAt
        act[peerId] = date
        teamDirectLastActivityAt = act
        if activeTeamDirectPeerId != peerId {
            var u = unreadOverride
            u[peerId] = (u[peerId] ?? 0) + 1
            unreadOverride = u
        }
        refreshTeamThreadsFromSnapshot()
    }

    private func refreshTeamThreadsFromSnapshot() {
        guard !lastTeamDirectorySnapshot.isEmpty else { return }
        syncTeamThreads(from: lastTeamDirectorySnapshot, currentUserId: lastTeamDirectoryUserId)
    }

    func applyTeamGroupOutgoing(body: String, date: Date) {
        teamGroupPreviewBody = Self.truncatePreview(body)
        teamGroupPreviewTime = Self.formatShortListTime(date)
        refreshTeamThreadsFromSnapshot()
    }

    /// Nuevo mensaje en el grupo (p. ej. Realtime); `senderId` es quien escribe.
    func applyTeamGroupIncoming(fromSender senderId: UUID, body: String, date: Date, currentUserId: UUID) {
        guard senderId != currentUserId else { return }
        teamGroupPreviewBody = Self.truncatePreview(body)
        teamGroupPreviewTime = Self.formatShortListTime(date)
        if !activeTeamGroupChatOpen {
            var u = unreadOverride
            let gid = ChatThread.teamGroupThreadId
            u[gid] = (u[gid] ?? 0) + 1
            unreadOverride = u
        }
        refreshTeamThreadsFromSnapshot()
    }

    private static func truncatePreview(_ body: String) -> String {
        let t = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= 80 { return t }
        return String(t.prefix(77)) + "…"
    }

    private static func formatShortListTime(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f.string(from: date)
        }
        if cal.isDateInYesterday(date) { return "Ayer" }
        let f = DateFormatter()
        f.dateFormat = "d/M"
        return f.string(from: date)
    }

    /// Registra un mensaje saliente «desde IA» hacia un compañero (actualiza lista de Chat y badge).
    func applyTeamCoordinatorOutreach(peerUserId: UUID, line: String) {
        var p = teamCoordinatorPeerPreview
        p[peerUserId] = line
        teamCoordinatorPeerPreview = p
        var u = unreadOverride
        u[peerUserId] = max(1, u[peerUserId] ?? 1)
        unreadOverride = u
        var act = teamDirectLastActivityAt
        act[peerUserId] = Date()
        teamDirectLastActivityAt = act
        refreshTeamThreadsFromSnapshot()
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
        switch thread.kind {
        case .teamGroup:
            teamGroupChatThread = nil
            teamGroupPreviewBody = nil
            teamGroupPreviewTime = nil
        case .teamDirect:
            teamDirectChatThreads.removeAll { $0.id == thread.id }
            if let pid = thread.peerUserId {
                var tp = teamCoordinatorPeerPreview
                tp.removeValue(forKey: pid)
                teamCoordinatorPeerPreview = tp
                var db = teamDirectPreviewBody
                db.removeValue(forKey: pid)
                teamDirectPreviewBody = db
                var dt = teamDirectPreviewTime
                dt.removeValue(forKey: pid)
                teamDirectPreviewTime = dt
                var la = teamDirectLastActivityAt
                la.removeValue(forKey: pid)
                teamDirectLastActivityAt = la
                var ct = coordinatorTasksByPeer
                ct.removeValue(forKey: pid)
                coordinatorTasksByPeer = ct
                bumpCoordinatorTimeline()
            }
        case .lead:
            liveThreads.removeAll { $0.id == thread.id }
        }
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
