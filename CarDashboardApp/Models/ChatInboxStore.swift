import CryptoKit
import Foundation
import SwiftUI
import Supabase
import UIKit

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
    /// Quien envió la tarea (coordinador / Viera).
    let senderUserId: UUID
    /// Destinatario asignado (clave del bucket en `coordinatorTasksByPeer`).
    let peerUserId: UUID
    var title: String
    var body: String
    /// `nil` hasta que el compañero pulse «Aceptar tarea».
    var acceptedAt: Date?
    /// Plazo acordado (por defecto 2 h desde el envío; el remitente puede cambiarlo).
    var deadline: Date
    var createdAt: Date?
    var steps: [CoordinatorTaskStep]
    /// Foto del vehículo asignado (referencia visual en la tarjeta).
    var referenceImageData: Data?

    var isComplete: Bool {
        !steps.isEmpty && steps.allSatisfy(\.verified)
    }

    init(
        id: UUID = UUID(),
        senderUserId: UUID,
        peerUserId: UUID,
        title: String,
        body: String,
        acceptedAt: Date? = nil,
        deadline: Date,
        createdAt: Date? = nil,
        steps: [CoordinatorTaskStep],
        referenceImageData: Data? = nil
    ) {
        self.id = id
        self.senderUserId = senderUserId
        self.peerUserId = peerUserId
        self.title = title
        self.body = body
        self.acceptedAt = acceptedAt
        self.deadline = deadline
        self.createdAt = createdAt
        self.steps = steps
        self.referenceImageData = referenceImageData
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
    /// El chat de lead CRM (WhatsApp/Instagram) está abierto en primer plano.
    @Published var activeLeadThreadId: UUID?
    /// El chat grupal «Mi equipo» está en primer plano.
    @Published var activeTeamGroupChatOpen: Bool = false
    /// Vista previa CRM anterior por hilo (detectar mensajes nuevos → notificación).
    private var crmLeadSnapshot: [UUID: CrmLeadSnapshot] = [:]
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
    private var blockedUserIdsForSync: Set<UUID> = []
    @Published private(set) var pinOverride: [UUID: Bool] = [:]
    @Published private(set) var unreadOverride: [UUID: Int] = [:]

    // MARK: - Chats reales del CRM (WhatsApp / Instagram del concesionario)

    /// Id de conversación del backend (CRM) por hilo mostrado en «Generales».
    @Published private(set) var crmConversationIdByThread: [UUID: String] = [:]
    /// Teléfono / contact_phone / wa_user_id del CRM por hilo.
    @Published private(set) var crmWaUserIdByThread: [UUID: String] = [:]
    /// Estado de la IA (encendida/apagada) por hilo del CRM.
    @Published private(set) var crmAiActiveByThread: [UUID: Bool] = [:]
    @Published private(set) var phoneScannedThreadIds: Set<UUID> = []
    /// Ya se cargaron conversaciones reales del CRM al menos una vez.
    @Published private(set) var crmLoadedOnce = false

    /// Marca localmente el estado de la IA de un hilo (respuesta inmediata al pulsar).
    @MainActor
    func setCrmAiActiveLocal(threadId: UUID, active: Bool) {
        crmAiActiveByThread[threadId] = active
    }

    /// ¿Hay al menos un chat con la IA encendida? (para el botón global).
    var anyCrmAiActive: Bool {
        crmAiActiveByThread.values.contains(true)
    }

    /// Marca TODOS los chats del CRM como encendidos/apagados (respuesta inmediata).
    @MainActor
    func setAllCrmAiActiveLocal(_ active: Bool) {
        for key in crmAiActiveByThread.keys {
            crmAiActiveByThread[key] = active
        }
    }

    /// Teléfono marcable del lead (WhatsApp wa_user_id, Instagram contact_phone o número en mensajes).
    func contactPhone(for thread: ChatThread) -> String? {
        guard thread.kind == .lead else { return nil }

        switch thread.socialSource {
        case .whatsApp:
            if let raw = crmWaUserIdByThread[thread.id],
               let phone = PhoneCallLauncher.whatsAppPhone(from: raw) {
                return phone
            }
            if let fromTitle = PhoneCallLauncher.whatsAppPhone(from: thread.title) {
                return fromTitle
            }
            return PhoneCallLauncher.extractPhone(from: thread.preview)

        case .instagram:
            if let raw = crmWaUserIdByThread[thread.id],
               let phone = PhoneCallLauncher.sanitizedDialString(from: raw) {
                return phone
            }
            return PhoneCallLauncher.extractPhone(from: thread.preview)
                ?? PhoneCallLauncher.extractPhone(from: thread.title)

        default:
            if let raw = crmWaUserIdByThread[thread.id],
               let phone = PhoneCallLauncher.sanitizedDialString(from: raw) {
                return phone
            }
            return PhoneCallLauncher.extractPhone(from: thread.preview)
                ?? PhoneCallLauncher.extractPhone(from: thread.title)
        }
    }

    /// ¿Este lead tiene número para llamar?
    func canCallLead(_ thread: ChatThread) -> Bool {
        contactPhone(for: thread) != nil
    }

    /// Número formateado para mostrar en UI (+34 637 360 011).
    func contactPhoneDisplay(for thread: ChatThread) -> String? {
        contactPhone(for: thread).map { PhoneCallLauncher.displayFormat($0) }
    }

    /// Hilos con teléfono extraído (WhatsApp, Instagram u otro origen).
    var leadThreadsWithPhone: [(thread: ChatThread, phone: String)] {
        liveThreads.compactMap { thread in
            guard thread.kind == .lead, let phone = contactPhone(for: thread) else { return nil }
            return (thread, phone)
        }
    }

    /// Descarga las conversaciones reales del CRM (mismas que la web drflow.es)
    /// y sustituye los chats de muestra de la pestaña «Generales».
    @MainActor
    func refreshCrmConversations(accessToken: String) async {
        do {
            let wasLoaded = crmLoadedOnce
            let previousSnapshot = crmLeadSnapshot

            let rows = try await CrmChatService.conversations(token: accessToken, limit: 100)
            var map: [UUID: String] = [:]
            var waMap: [UUID: String] = [:]
            var aiMap: [UUID: Bool] = [:]
            let threads: [ChatThread] = rows.map { row in
                let uuid = CrmChatService.stableUUID(for: "conv:\(row.id)")
                map[uuid] = row.id
                let isInstagram =
                    (row.source ?? "").lowercased().contains("instagram")
                    || (row.waUserId ?? "").hasPrefix("ig:")
                if isInstagram {
                    if let phoneRaw = row.contactPhone, !phoneRaw.isEmpty {
                        waMap[uuid] = phoneRaw
                    }
                } else if let phoneRaw = row.contactPhone ?? row.waUserId, !phoneRaw.isEmpty {
                    waMap[uuid] = phoneRaw
                }
                aiMap[uuid] = row.aiActive ?? true
                return Self.thread(fromCrm: row, uuid: uuid)
            }
            crmConversationIdByThread = map
            crmWaUserIdByThread = waMap
            crmAiActiveByThread = aiMap
            phoneScannedThreadIds = []
            liveThreads = threads
            crmLeadSnapshot = Dictionary(
                uniqueKeysWithValues: threads
                    .filter { $0.kind == .lead }
                    .map { ($0.id, CrmLeadSnapshot(preview: $0.preview, unread: $0.unread ?? 0)) }
            )
            crmLoadedOnce = true

            if wasLoaded {
                MessageNotificationService.notifyNewCrmMessages(
                    previous: previousSnapshot,
                    current: threads.filter { $0.kind == .lead },
                    activeThreadId: activeLeadThreadId
                )
            }

            await refreshLeadPhonesFromMessages(accessToken: accessToken)
            await enrichMissingContactPhotos(accessToken: accessToken)
        } catch {
            // Sin red o sin sesión: si nunca cargamos, se quedan las muestras.
        }
    }

    /// Si el listado no trae foto, intenta obtenerla con endpoints dedicados del CRM.
    @MainActor
    private func enrichMissingContactPhotos(accessToken: String) async {
        let targets = liveThreads.filter { $0.kind == .lead && $0.avatarCarURL == nil }
        for thread in targets.prefix(40) {
            guard let convId = crmConversationIdByThread[thread.id] else { continue }
            let wa = crmWaUserIdByThread[thread.id]
            guard let url = try? await CrmChatService.fetchContactProfilePhotoURL(
                token: accessToken,
                conversationId: convId,
                waUserId: wa
            ) else { continue }
            guard let idx = liveThreads.firstIndex(where: { $0.id == thread.id }) else { continue }
            liveThreads[idx] = liveThreads[idx].withAvatarCarURL(url)
        }
    }

    /// Busca teléfonos en el historial (Instagram suele darlo en un mensaje).
    @MainActor
    func refreshLeadPhonesFromMessages(accessToken: String) async {
        let targets = liveThreads.filter { thread in
            thread.kind == .lead && contactPhone(for: thread) == nil
        }
        for thread in targets.prefix(25) where !phoneScannedThreadIds.contains(thread.id) {
            guard let backendId = crmConversationIdByThread[thread.id] else { continue }
            do {
                let rows = try await CrmChatService.messages(
                    token: accessToken,
                    conversationId: backendId,
                    limit: 50
                )
                let texts = rows.compactMap(\.textContent)
                if crmWaUserIdByThread[thread.id] == nil,
                   let phone = PhoneCallLauncher.firstPhone(in: texts) {
                    crmWaUserIdByThread[thread.id] = phone
                }
            } catch {
                continue
            }
            phoneScannedThreadIds.insert(thread.id)
        }
    }

    private static func thread(fromCrm row: CrmChatService.Conversation, uuid: UUID) -> ChatThread {
        let isInstagram =
            (row.source ?? "").lowercased().contains("instagram")
            || (row.waUserId ?? "").hasPrefix("ig:")
        let fallbackName = (row.waUserId ?? "Contacto").replacingOccurrences(of: "ig:", with: "@")
        let name = (row.contactName?.isEmpty == false) ? row.contactName! : fallbackName
        return ChatThread(
            id: uuid,
            title: name,
            preview: row.lastMessage ?? "",
            time: CrmChatService.listTime(fromISO: row.updatedAt),
            unread: (row.unreadCount ?? 0) > 0 ? row.unreadCount : nil,
            avatarInitial: String(name.prefix(1)).uppercased(),
            avatarIcon: nil,
            avatarR: isInstagram ? 0.69 : 0.16,
            avatarG: isInstagram ? 0.32 : 0.68,
            avatarB: isInstagram ? 0.87 : 0.38,
            avatarCarURL: CrmChatService.resolveMediaURL(row.contactPhotoUrl),
            socialSource: isInstagram ? .instagram : .whatsApp,
            isVerified: false,
            isPinned: row.pinned ?? false,
            kind: .lead,
            peerUserId: nil,
            readReceipt: .none,
            showOpenButton: false
        )
    }

    private func bumpCoordinatorTimeline() {
        coordinatorTimelineTick += 1
    }

    func coordinatorTasks(forPeer peerUserId: UUID) -> [CoordinatorOutboundTask] {
        coordinatorTasksByPeer[peerUserId] ?? []
    }

    /// En un DM equipo con `otherUserId`: tareas que enviaste a esa persona y las que esa persona te envió a ti.
    func coordinatorTasksInTeamDirectThread(myUserId: UUID, otherUserId: UUID) -> [CoordinatorOutboundTask] {
        let toOther = (coordinatorTasksByPeer[otherUserId] ?? []).filter { $0.senderUserId == myUserId }
        let fromOther = (coordinatorTasksByPeer[myUserId] ?? []).filter { $0.senderUserId == otherUserId }
        return (toOther + fromOther).sorted {
            let a = $0.createdAt ?? .distantPast
            let b = $1.createdAt ?? .distantPast
            if a != b { return a < b }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    /// Tareas pendientes asignadas al usuario actual (para el panel Inicio).
    func myPendingAssignedCoordinatorTasks(myUserId: UUID) -> [CoordinatorOutboundTask] {
        (coordinatorTasksByPeer[myUserId] ?? []).filter { !$0.isComplete }
    }

    /// Crea la tarea en Supabase y la fusiona en la bandeja local.
    func createCoordinatorTaskSynced(
        senderUserId: UUID,
        recipientUserId: UUID,
        title: String,
        body: String,
        stepInstructions: [String],
        deadline: Date,
        referenceImageData: Data?
    ) async throws {
        let b64 = referenceImageData.map { $0.base64EncodedString() }
        let row = try await TeamCoordinatorTasksService.create(
            recipientId: recipientUserId,
            title: title,
            body: body,
            deadline: deadline,
            stepInstructions: stepInstructions,
            referenceImageBase64: b64,
            client: SupabaseClientProvider.shared
        )
        await MainActor.run {
            mergeCoordinatorTaskFromServer(row)
        }
    }

    func refreshCoordinatorTasksFromServer(currentUserId: UUID) async {
        do {
            let rows = try await TeamCoordinatorTasksService.fetchInvolving(
                userId: currentUserId,
                client: SupabaseClientProvider.shared
            )
            await MainActor.run {
                for row in rows {
                    mergeCoordinatorTaskFromServer(row)
                }
            }
        } catch {
            // Tabla ausente o red: se mantiene estado local.
        }
    }

    func mergeCoordinatorTaskFromServer(_ row: TeamCoordinatorTasksService.Row) {
        let recipientId = row.recipientId
        let existing = coordinatorTasksByPeer[recipientId]?.first(where: { $0.id == row.id })
        let task = Self.coordinatorTask(from: row, mergingExisting: existing)
        var arr = coordinatorTasksByPeer[recipientId] ?? []
        if let i = arr.firstIndex(where: { $0.id == task.id }) {
            arr[i] = task
        } else {
            arr.append(task)
        }
        coordinatorTasksByPeer[recipientId] = arr
        bumpCoordinatorTimeline()
    }

    func updateCoordinatorTaskDeadline(taskId: UUID, newDeadline: Date, currentUserId: UUID) async throws {
        let allowed = await MainActor.run { () -> Bool in
            guard let pair = findCoordinatorTask(taskId: taskId) else { return false }
            return pair.task.senderUserId == currentUserId
        }
        guard allowed else { return }
        let row = try await TeamCoordinatorTasksService.updateDeadline(
            taskId: taskId,
            deadline: newDeadline,
            client: SupabaseClientProvider.shared
        )
        await MainActor.run {
            mergeCoordinatorTaskFromServer(row)
        }
    }

    private func findCoordinatorTask(taskId: UUID) -> (recipientKey: UUID, task: CoordinatorOutboundTask)? {
        for (key, tasks) in coordinatorTasksByPeer {
            if let t = tasks.first(where: { $0.id == taskId }) {
                return (key, t)
            }
        }
        return nil
    }

    private static func coordinatorTask(from row: TeamCoordinatorTasksService.Row, mergingExisting: CoordinatorOutboundTask?) -> CoordinatorOutboundTask {
        let deadline = TeamCoordinatorTasksService.parseDate(row.deadlineAt) ?? Date().addingTimeInterval(7200)
        let accepted = row.acceptedAt.flatMap { TeamCoordinatorTasksService.parseDate($0) }
        let created = TeamCoordinatorTasksService.parseDate(row.createdAt)
        let refData = row.referenceImageBase64.flatMap { Data(base64Encoded: $0) }
        let instructions = row.stepInstructions
        let steps: [CoordinatorTaskStep]
        if let existing = mergingExisting, existing.id == row.id, existing.steps.count == instructions.count {
            steps = zip(instructions, existing.steps).map { instr, prev in
                if prev.instruction == instr {
                    prev
                } else {
                    CoordinatorTaskStep(instruction: instr)
                }
            }
        } else {
            steps = instructions.map { CoordinatorTaskStep(instruction: $0) }
        }
        return CoordinatorOutboundTask(
            id: row.id,
            senderUserId: row.senderId,
            peerUserId: row.recipientId,
            title: row.title,
            body: row.body,
            acceptedAt: accepted,
            deadline: deadline,
            createdAt: created,
            steps: steps,
            referenceImageData: refData
        )
    }

    func acceptCoordinatorTask(recipientUserId: UUID, taskId: UUID) {
        Task {
            do {
                let row = try await TeamCoordinatorTasksService.markAccepted(
                    taskId: taskId,
                    client: SupabaseClientProvider.shared
                )
                await MainActor.run {
                    mergeCoordinatorTaskFromServer(row)
                }
            } catch {
                await MainActor.run {
                    guard var arr = coordinatorTasksByPeer[recipientUserId],
                          let i = arr.firstIndex(where: { $0.id == taskId })
                    else { return }
                    arr[i].acceptedAt = Date()
                    coordinatorTasksByPeer[recipientUserId] = arr
                    bumpCoordinatorTimeline()
                }
            }
        }
    }

    func setCoordinatorStepProof(recipientUserId: UUID, taskId: UUID, stepId: UUID, imageData: Data) {
        guard var arr = coordinatorTasksByPeer[recipientUserId],
              let ti = arr.firstIndex(where: { $0.id == taskId })
        else { return }
        var task = arr[ti]
        guard let si = task.steps.firstIndex(where: { $0.id == stepId }) else { return }
        task.steps[si].proofImageData = imageData
        arr[ti] = task
        coordinatorTasksByPeer[recipientUserId] = arr
        bumpCoordinatorTimeline()
    }

    func verifyCoordinatorStep(recipientUserId: UUID, taskId: UUID, stepId: UUID) {
        guard var arr = coordinatorTasksByPeer[recipientUserId],
              let ti = arr.firstIndex(where: { $0.id == taskId })
        else { return }
        var task = arr[ti]
        guard let si = task.steps.firstIndex(where: { $0.id == stepId }) else { return }
        guard task.steps[si].proofImageData != nil else { return }
        task.steps[si].verified = true
        arr[ti] = task
        coordinatorTasksByPeer[recipientUserId] = arr
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
    func syncTeamThreads(
        from directory: [CommunityProfilesService.DirectoryRow],
        currentUserId: UUID?,
        blockedUserIds: Set<UUID> = []
    ) {
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
            .filter { !blockedUserIds.contains($0.userId) }
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
        b[peerId] = TeamDirectVoiceStorage.inboxPreviewBody(for: body)
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
        b[peerId] = TeamDirectVoiceStorage.inboxPreviewBody(for: body)
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

    func refreshTeamThreadsFromSnapshot(blockedUserIds: Set<UUID>? = nil) {
        if let ids = blockedUserIds {
            blockedUserIdsForSync = ids
        }
        guard !lastTeamDirectorySnapshot.isEmpty else { return }
        syncTeamThreads(
            from: lastTeamDirectorySnapshot,
            currentUserId: lastTeamDirectoryUserId,
            blockedUserIds: blockedUserIdsForSync
        )
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

// MARK: - Supabase: tareas coordinador (mismo módulo que la bandeja; evita fallos si el .swift suelto no está en el target)

enum TeamCoordinatorTasksService {
    private static let table = "team_coordinator_tasks"

    struct Row: Decodable, Sendable {
        let id: UUID
        let senderId: UUID
        let recipientId: UUID
        let title: String
        let body: String
        let deadlineAt: String
        let acceptedAt: String?
        let stepInstructions: [String]
        let referenceImageBase64: String?
        let createdAt: String

        enum CodingKeys: String, CodingKey {
            case id
            case senderId = "sender_id"
            case recipientId = "recipient_id"
            case title
            case body
            case deadlineAt = "deadline_at"
            case acceptedAt = "accepted_at"
            case stepInstructions = "step_instructions"
            case referenceImageBase64 = "reference_image_base64"
            case createdAt = "created_at"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            senderId = try c.decode(UUID.self, forKey: .senderId)
            recipientId = try c.decode(UUID.self, forKey: .recipientId)
            title = try c.decode(String.self, forKey: .title)
            body = try c.decode(String.self, forKey: .body)
            deadlineAt = try c.decode(String.self, forKey: .deadlineAt)
            acceptedAt = try c.decodeIfPresent(String.self, forKey: .acceptedAt)
            referenceImageBase64 = try c.decodeIfPresent(String.self, forKey: .referenceImageBase64)
            createdAt = try c.decode(String.self, forKey: .createdAt)
            if let arr = try? c.decode([String].self, forKey: .stepInstructions) {
                stepInstructions = arr
            } else if let objs = try? c.decode([[String: String]].self, forKey: .stepInstructions) {
                stepInstructions = objs.compactMap { $0["instruction"] ?? $0["text"] }
            } else {
                stepInstructions = []
            }
        }
    }

    private struct InsertPayload: Encodable {
        let recipientId: UUID
        let title: String
        let body: String
        let deadlineAt: String
        let stepInstructions: [String]
        let referenceImageBase64: String?

        enum CodingKeys: String, CodingKey {
            case recipientId = "recipient_id"
            case title
            case body
            case deadlineAt = "deadline_at"
            case stepInstructions = "step_instructions"
            case referenceImageBase64 = "reference_image_base64"
        }
    }

    private struct AcceptPatch: Encodable {
        let acceptedAt: String

        enum CodingKeys: String, CodingKey {
            case acceptedAt = "accepted_at"
        }
    }

    private struct DeadlinePatch: Encodable {
        let deadlineAt: String

        enum CodingKeys: String, CodingKey {
            case deadlineAt = "deadline_at"
        }
    }

    private static func isoString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    static func parseDate(_ s: String) -> Date? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: trimmed) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        if let d = f2.date(from: trimmed) { return d }

        // Postgres/PostgREST a veces devuelve espacio en vez de «T» entre fecha y hora.
        var normalized = trimmed
        if !normalized.contains("T"), let sp = normalized.firstIndex(of: " ") {
            let head = normalized[..<sp]
            if head.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
                normalized.replaceSubrange(sp...sp, with: "T")
                if let d = f2.date(from: normalized) { return d }
                if let d = f1.date(from: normalized) { return d }
            }
        }

        // Microsegundos largos (p. ej. .123456): recortar a 3 dígitos fraccionarios para ISO8601.
        if let range = normalized.range(of: #"\.\d{4,}"#, options: .regularExpression) {
            let fracStart = normalized.index(after: range.lowerBound)
            let cut = normalized.index(fracStart, offsetBy: 2, limitedBy: range.upperBound) ?? fracStart
            normalized = String(normalized[..<fracStart]) + String(normalized[fracStart...cut]) + String(normalized[range.upperBound...])
            if let d = f1.date(from: normalized) { return d }
            if let d = f2.date(from: normalized) { return d }
        }

        return nil
    }

    static func fetchInvolving(userId: UUID, client: SupabaseClient) async throws -> [Row] {
        let filter = "recipient_id.eq.\(userId.uuidString.lowercased()),sender_id.eq.\(userId.uuidString.lowercased())"
        return try await client
            .from(table)
            .select()
            .or(filter)
            .order("created_at", ascending: false)
            .limit(200)
            .execute()
            .value
    }

    static func create(
        recipientId: UUID,
        title: String,
        body: String,
        deadline: Date,
        stepInstructions: [String],
        referenceImageBase64: String?,
        client: SupabaseClient
    ) async throws -> Row {
        let payload = InsertPayload(
            recipientId: recipientId,
            title: title,
            body: body,
            deadlineAt: isoString(deadline),
            stepInstructions: stepInstructions,
            referenceImageBase64: referenceImageBase64
        )
        return try await client
            .from(table)
            .insert(payload, returning: .representation)
            .select()
            .single()
            .execute()
            .value
    }

    static func markAccepted(taskId: UUID, client: SupabaseClient) async throws -> Row {
        let patch = AcceptPatch(acceptedAt: isoString(Date()))
        return try await client
            .from(table)
            .update(patch)
            .eq("id", value: taskId.uuidString.lowercased())
            .select()
            .single()
            .execute()
            .value
    }

    static func updateDeadline(taskId: UUID, deadline: Date, client: SupabaseClient) async throws -> Row {
        let patch = DeadlinePatch(deadlineAt: isoString(deadline))
        return try await client
            .from(table)
            .update(patch)
            .eq("id", value: taskId.uuidString.lowercased())
            .select()
            .single()
            .execute()
            .value
    }
}

// MARK: - Cliente del backend del CRM (drflowbackend) — chats reales de WhatsApp/Instagram
//
// Usa los MISMOS endpoints que la web drflow.es, autenticados con el token
// de la sesión de Supabase del usuario (mismo proyecto Supabase que el CRM).

enum CrmChatService {
    static let baseURL = URL(string: "https://drflowbackend.onrender.com")!

    enum ServiceError: Error {
        case badResponse
    }

    // MARK: Modelos (decodificación tolerante: los ids pueden venir como número o texto)

    struct Conversation: Identifiable {
        let id: String
        let contactName: String?
        let contactPhotoUrl: String?
        let lastMessage: String?
        let unreadCount: Int?
        let updatedAt: String?
        let contactPhone: String?
        let waUserId: String?
        let source: String?
        let pinned: Bool?
        let aiActive: Bool?
        let vehicleId: String?
    }

    struct Message: Identifiable {
        let id: String
        let textContent: String?
        let senderType: String?
        let createdAt: String?
        let messageType: String?
        let mediaUrl: String?
        let mediaType: String?
        let mediaContent: String?
        let mediaFilename: String?
    }

    // MARK: Peticiones

    // MARK: Peticiones

    /// Extrae la URL de foto de perfil del contacto desde la fila del CRM (nombres alternativos).
    static func extractContactPhotoURL(from row: [String: Any]) -> String? {
        let directKeys = [
            "contact_photo_url", "contactPhotoUrl", "contact_photo",
            "profile_picture_url", "profilePictureUrl", "profile_pic_url",
            "profile_pic", "profilePic", "avatar_url", "avatarUrl",
            "photo_url", "photoUrl", "picture_url", "pictureUrl",
            "wa_profile_picture", "whatsapp_profile_picture", "profile_picture",
        ]
        for key in directKeys {
            if let raw = flexString(row[key])?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                return raw
            }
        }
        if let nested = row["contact"] as? [String: Any],
           let fromContact = extractContactPhotoURL(from: nested) {
            return fromContact
        }
        if let nested = row["profile"] as? [String: Any],
           let fromProfile = extractContactPhotoURL(from: nested) {
            return fromProfile
        }
        if let data = row["data"] as? [String: Any],
           let fromData = extractContactPhotoURL(from: data) {
            return fromData
        }
        if let urlObj = row["contact_photo_url"] as? [String: Any],
           let nested = extractContactPhotoURL(from: urlObj) {
            return nested
        }
        return nil
    }

    /// Convierte rutas relativas del CRM o data-URLs en `URL` válida.
    static func resolveMediaURL(_ raw: String?) -> URL? {
        guard var trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        if trimmed.hasPrefix("data:") { return URL(string: trimmed) }
        if trimmed.hasPrefix("//") { trimmed = "https:" + trimmed }
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        if trimmed.hasPrefix("/") {
            var base = baseURL.absoluteString
            if base.hasSuffix("/") { base.removeLast() }
            return URL(string: base + trimmed)
        }
        if !trimmed.contains("://"), trimmed.contains(".") {
            return URL(string: "https://" + trimmed)
        }
        return URL(string: trimmed)
    }

    /// Intenta obtener la foto de perfil cuando no viene en el listado de conversaciones.
    static func fetchContactProfilePhotoURL(
        token: String,
        conversationId: String,
        waUserId: String?
    ) async throws -> URL? {
        let encConv = conversationId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? conversationId
        var paths = [
            "/api/whatsapp/get_contact_profile_picture?conversationId=\(encConv)",
            "/api/whatsapp/get_profile_picture?conversationId=\(encConv)",
            "/api/whatsapp/get_contact_photo?conversationId=\(encConv)",
        ]
        if let wa = waUserId?.trimmingCharacters(in: .whitespacesAndNewlines), !wa.isEmpty {
            let encWa = wa.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? wa
            paths.append(contentsOf: [
                "/api/whatsapp/get_contact_profile_picture?wa_user_id=\(encWa)",
                "/api/whatsapp/get_profile_picture?wa_user_id=\(encWa)",
                "/api/whatsapp/get_contact_photo?wa_user_id=\(encWa)",
            ])
        }
        for path in paths {
            guard let json = try? await getJSON(path: path, token: token) else { continue }
            if let raw = extractContactPhotoURL(from: json)
                ?? flexString(json["url"])
                ?? flexString(json["photo_url"])
                ?? flexString(json["profilePictureUrl"]),
               let resolved = resolveMediaURL(raw) {
                return resolved
            }
            if let data = json["data"] as? [String: Any],
               let raw = extractContactPhotoURL(from: data),
               let resolved = resolveMediaURL(raw) {
                return resolved
            }
        }
        return nil
    }

    static func conversations(token: String, limit: Int = 100) async throws -> [Conversation] {
        let json = try await getJSON(
            path: "/api/whatsapp/get_conversations?limit=\(limit)&offset=0",
            token: token
        )
        let rows = (json["data"] as? [[String: Any]]) ?? (json["conversations"] as? [[String: Any]]) ?? []
        return rows.map { r in
            Conversation(
                id: flexString(r["id"]) ?? UUID().uuidString,
                contactName: r["contact_name"] as? String,
                contactPhotoUrl: CrmChatService.extractContactPhotoURL(from: r),
                lastMessage: r["last_message"] as? String,
                unreadCount: flexInt(r["unread_count"]),
                updatedAt: r["updated_at"] as? String,
                contactPhone: (r["contact_phone"] as? String)
                    ?? (r["phone"] as? String)
                    ?? (r["phone_number"] as? String)
                    ?? (r["telefono"] as? String),
                waUserId: r["wa_user_id"] as? String,
                source: r["source"] as? String,
                pinned: (r["pinned"] as? Bool) ?? (r["is_pinned"] as? Bool),
                aiActive: r["ai_active"] as? Bool,
                vehicleId: flexString(r["vehicle_id"])
                    ?? flexString(r["vehicleId"])
                    ?? flexString(r["car_id"])
                    ?? flexString(r["carId"])
            )
        }
    }

    static func messages(token: String, conversationId: String, limit: Int = 100) async throws -> [Message] {
        let encoded = conversationId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? conversationId
        let json = try await getJSON(
            path: "/api/whatsapp/get_messages?conversationId=\(encoded)&limit=\(limit)",
            token: token
        )
        let rows = (json["data"] as? [[String: Any]]) ?? []
        return rows.map { r in
            Message(
                id: flexString(r["id"]) ?? UUID().uuidString,
                textContent: (r["text_content"] as? String) ?? (r["body"] as? String),
                senderType: r["sender_type"] as? String,
                createdAt: r["created_at"] as? String,
                messageType: r["message_type"] as? String,
                mediaUrl: r["media_url"] as? String,
                mediaType: r["media_type"] as? String,
                mediaContent: r["media_content"] as? String,
                mediaFilename: r["media_filename"] as? String
            )
        }
    }

    /// Apaga o enciende la IA para esa conversación (para que entre un comercial).
    static func setAiActive(token: String, conversationId: String, active: Bool) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/whatsapp/ai_toggle"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "conversationId": conversationId,
            "active": active,
        ])
        let (_, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw ServiceError.badResponse
        }
    }

    /// Apaga/enciende la IA en TODOS los chats (WhatsApp + Instagram) de golpe.
    static func setAiActiveAll(token: String, active: Bool) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/whatsapp/ai_toggle_all"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["active": active])
        let (_, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw ServiceError.badResponse
        }
    }

    /// Envía un mensaje de texto al cliente (WhatsApp o Instagram, según la conversación).
    static func send(token: String, conversationId: String, text: String) async throws {
        try await postJSON(
            path: "/api/whatsapp/send_message",
            token: token,
            body: [
                "conversationId": conversationId,
                "textContent": text,
            ]
        )
    }

    /// Envía una nota de voz al cliente por WhatsApp/Instagram.
    static func sendAudio(token: String, conversationId: String, fileURL: URL) async throws {
        let data = try Data(contentsOf: fileURL)
        guard data.count > 400 else { throw ServiceError.badResponse }
        let b64 = data.base64EncodedString()
        let filename = fileURL.lastPathComponent.isEmpty ? "voice.m4a" : fileURL.lastPathComponent

        let payloads: [[String: Any]] = [
            [
                "conversationId": conversationId,
                "textContent": "",
                "messageType": "audio",
                "mediaType": "audio/mp4",
                "mediaContent": b64,
                "mediaFilename": filename,
            ],
            [
                "conversationId": conversationId,
                "textContent": "",
                "messageType": "ptt",
                "mediaType": "audio/ogg; codecs=opus",
                "mediaContent": b64,
                "mediaFilename": filename,
            ],
            [
                "conversationId": conversationId,
                "audioBase64": b64,
                "mimeType": "audio/mp4",
            ],
        ]

        var lastError: Error = ServiceError.badResponse
        for body in payloads {
            do {
                try await postJSON(path: "/api/whatsapp/send_message", token: token, body: body)
                return
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// ¿Es un mensaje de audio / nota de voz?
    static func isAudioMessage(_ row: Message) -> Bool {
        let type = combinedMediaType(row).lowercased()
        if type.contains("audio") || type.contains("ptt") || type.contains("voice") {
            return true
        }
        if let url = row.mediaUrl?.lowercased() {
            return [".ogg", ".opus", ".m4a", ".mp3", ".aac", ".amr", ".mp4", ".webm"]
                .contains { url.contains($0) }
        }
        if row.mediaContent != nil, type.contains("ogg") || type.contains("opus") || type.contains("mpeg") {
            return true
        }
        return false
    }

    /// URL o data-URL del audio del mensaje CRM.
    static func audioURL(for row: Message) -> URL? {
        if let resolved = resolveMediaURL(row.mediaUrl) { return resolved }
        guard isAudioMessage(row), let b64 = row.mediaContent?.trimmingCharacters(in: .whitespacesAndNewlines), !b64.isEmpty else {
            return nil
        }
        let clean = b64.contains(",") ? String(b64.split(separator: ",").last ?? "") : b64
        let mime = combinedMediaType(row).contains("/") ? combinedMediaType(row) : "audio/ogg"
        return URL(string: "data:\(mime);base64,\(clean)")
    }

    private static func combinedMediaType(_ row: Message) -> String {
        (row.mediaType ?? row.messageType ?? "")
    }

    private static func postJSON(path: String, token: String, body: [String: Any]) async throws {
        guard let url = URL(string: baseURL.absoluteString + path) else { throw ServiceError.badResponse }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            let status = (res as? HTTPURLResponse)?.statusCode ?? -1
            let snippet = String(data: data.prefix(240), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let detail = snippet.isEmpty ? "HTTP \(status)" : "HTTP \(status): \(snippet)"
            throw NSError(
                domain: "CrmChat",
                code: status,
                userInfo: [NSLocalizedDescriptionKey: detail]
            )
        }
    }

    private static func getJSON(path: String, token: String) async throws -> [String: Any] {
        guard let url = URL(string: baseURL.absoluteString + path) else { throw ServiceError.badResponse }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse, (200 ... 299).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ServiceError.badResponse }
        return json
    }

    // MARK: Utilidades

    private static func flexString(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    private static func flexInt(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }

    /// UUID determinista a partir del id del backend (mismo chat → mismo UUID al refrescar).
    static func stableUUID(for backendId: String) -> UUID {
        let digest = SHA256.hash(data: Data(backendId.utf8))
        let bytes = Array(digest.prefix(16))
        let uuid: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuid)
    }

    static func parseISO(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: s) { return d }
        // Postgres a veces devuelve "2026-06-07 18:30:00.123+00" (espacio en vez de T)
        return withFraction.date(from: s.replacingOccurrences(of: " ", with: "T"))
    }

    /// Hora corta para la fila de la lista: "9:42", "Ayer", "sáb", "18/03".
    static func listTime(fromISO s: String?) -> String {
        guard let date = parseISO(s) else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return clockString(date) }
        if cal.isDateInYesterday(date) { return "Ayer" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: Date())).day ?? 99
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "es_ES")
        fmt.dateFormat = days < 7 ? "EEE" : "dd/MM"
        return fmt.string(from: date)
    }

    /// Hora "22:15" para la burbuja del mensaje.
    static func clockTime(fromISO s: String?) -> String {
        guard let date = parseISO(s) else { return "" }
        return clockString(date)
    }

    private static func clockString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "es_ES")
        fmt.dateFormat = "H:mm"
        return fmt.string(from: date)
    }
}

// MARK: - Carga de fotos de perfil de contactos CRM

enum CrmContactPhotoLoader {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 80 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    static func load(url: URL, accessToken: String?) async -> UIImage? {
        let cacheKey = url.absoluteString
        if let cached = ImageCacheService.shared.image(forKey: cacheKey) {
            return cached
        }
        if url.scheme?.lowercased() == "data" {
            let raw = url.absoluteString
            if let comma = raw.firstIndex(of: ",") {
                let payload = String(raw[raw.index(after: comma)...])
                if let data = Data(base64Encoded: payload), let img = UIImage(data: data) {
                    ImageCacheService.shared.store(img, forKey: cacheKey)
                    return img
                }
            }
            return nil
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        if needsAuthorization(for: url), let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200 ... 299).contains(http.statusCode),
                  let img = UIImage(data: data)
            else { return nil }
            ImageCacheService.shared.store(img, forKey: cacheKey)
            return img
        } catch {
            return nil
        }
    }

    private static func needsAuthorization(for url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return url.path.hasPrefix("/api/")
        }
        return host.contains("drflowbackend") || host.contains("drflow")
    }
}

// MARK: - Llamadas telefónicas (tel:)

extension Notification.Name {
    static let phoneCallDidFail = Notification.Name("Drflow.phoneCallDidFail")
}

enum PhoneCallLauncher {
    /// Extrae el teléfono de un wa_user_id de WhatsApp (34600123456, +34…, @s.whatsapp.net).
    static func whatsAppPhone(from raw: String) -> String? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        if lower.hasPrefix("ig:") { return nil }

        if let at = trimmed.firstIndex(of: "@") {
            trimmed = String(trimmed[..<at])
        }
        trimmed = trimmed.replacingOccurrences(of: " ", with: "")

        let hasPlus = trimmed.hasPrefix("+")
        let digits = trimmed.filter(\.isNumber)
        guard digits.count >= 9 else { return nil }

        // Móvil español sin prefijo (9 dígitos)
        if digits.count == 9, let first = digits.first, "6789".contains(first) {
            return "+34\(digits)"
        }
        // Con prefijo internacional
        if digits.count >= 10 || hasPlus {
            return "+\(digits)"
        }
        return digits
    }

    static func sanitizedDialString(from raw: String) -> String? {
        whatsAppPhone(from: raw) ?? {
            var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.lowercased().hasPrefix("ig:") { return nil }
            if let atRange = trimmed.range(of: "@") {
                trimmed = String(trimmed[..<atRange.lowerBound])
            }
            let hasPlus = trimmed.contains("+")
            let digits = trimmed.filter(\.isNumber)
            guard digits.count >= 9 else { return nil }
            if hasPlus || digits.count > 9 { return "+\(digits)" }
            return digits
        }()
    }

    /// Formato legible: +34637360011 → +34 637 360 011
    static func displayFormat(_ dial: String) -> String {
        let digits = dial.filter(\.isNumber)
        if dial.hasPrefix("+34") || (digits.count == 11 && digits.hasPrefix("34")) {
            let local = digits.count == 11 ? String(digits.suffix(9)) : String(digits.dropFirst(2))
            guard local.count == 9 else { return dial }
            let i = local.index(local.startIndex, offsetBy: 3)
            let j = local.index(i, offsetBy: 3)
            return "+34 \(local[..<i]) \(local[i..<j]) \(local[j...])"
        }
        if digits.count >= 9 {
            return dial.hasPrefix("+") ? dial : "+\(digits)"
        }
        return dial
    }

    static func extractPhone(from text: String) -> String? {
        let pattern = #"(?:\+?\d[\d\s\-().]{7,}\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text)
        else { return nil }
        return sanitizedDialString(from: String(text[swiftRange]))
    }

    /// Primer teléfono encontrado en una lista de mensajes (p. ej. Instagram).
    static func firstPhone(in texts: [String]) -> String? {
        for text in texts {
            if let phone = extractPhone(from: text) { return phone }
        }
        return nil
    }

    static func resolvedPhone(
        for thread: ChatThread,
        chatInbox: ChatInboxStore,
        crmLeads: [LeadCrm] = []
    ) -> String? {
        if let fromInbox = chatInbox.contactPhone(for: thread) {
            return fromInbox
        }
        guard thread.kind == .lead else { return nil }
        let key = thread.title.lowercased()
        if let lead = crmLeads.first(where: {
            $0.title.lowercased() == key
                || ($0.phone ?? "").lowercased().contains(key)
                || key.contains(($0.phone ?? "").lowercased())
        }), let phone = lead.phone, !phone.isEmpty {
            return whatsAppPhone(from: phone) ?? sanitizedDialString(from: phone)
        }
        return extractPhone(from: thread.preview) ?? extractPhone(from: thread.title)
    }

    private static func telURL(for dial: String) -> URL? {
        var allowed = CharacterSet.decimalDigits
        allowed.insert(charactersIn: "+")
        let encoded = dial.addingPercentEncoding(withAllowedCharacters: allowed) ?? dial
        return URL(string: "tel:\(encoded)")
    }

    @MainActor
    static func call(_ rawPhone: String) {
        guard let dial = sanitizedDialString(from: rawPhone),
              let url = telURL(for: dial)
        else { return }

        NotificationCenter.default.post(name: .phoneCallDidStart, object: nil)

        #if targetEnvironment(simulator)
        copyAndNotifyFailure(dial: dial, reason: "simulator")
        return
        #else
        UIApplication.shared.open(url, options: [:]) { success in
            if !success {
                Task { @MainActor in
                    copyAndNotifyFailure(dial: dial, reason: "unavailable")
                }
            }
        }
        #endif
    }

    @MainActor
    private static func copyAndNotifyFailure(dial: String, reason: String) {
        UIPasteboard.general.string = dial
        NotificationCenter.default.post(
            name: .phoneCallDidFail,
            object: nil,
            userInfo: ["number": dial, "reason": reason]
        )
    }
}
