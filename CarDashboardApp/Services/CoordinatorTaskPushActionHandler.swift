import EventKit
import Foundation
import Supabase
import UserNotifications

/// Identificadores de categoría / acción para push de `team_coordinator_tasks` (coinciden con el payload APNs).
enum CarHubNotificationCategories {
    static let coordinatorTask = "COORDINATOR_TASK"
    static let coordinatorTaskAcceptAction = "COORDINATOR_TASK_ACCEPT"
}

extension Notification.Name {
    /// Tras aceptar desde la notificación: refrescar tareas en la bandeja.
    static let coordinatorTaskAcceptedFromPush = Notification.Name("CarHub.coordinatorTaskAcceptedFromPush")
}

enum CoordinatorTaskNotificationRegistration {
    static func registerCategories() {
        let accept = UNNotificationAction(
            identifier: CarHubNotificationCategories.coordinatorTaskAcceptAction,
            title: "Aceptar",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: CarHubNotificationCategories.coordinatorTask,
            actions: [accept],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}

/// Respuesta a «Aceptar» en la push: marca la tarea en Supabase y crea evento en Calendario.
enum CoordinatorTaskPushActionHandler {
    static func handleAcceptIfNeeded(
        response: UNNotificationResponse,
        completion: @escaping () -> Void
    ) {
        guard response.actionIdentifier == CarHubNotificationCategories.coordinatorTaskAcceptAction else {
            completion()
            return
        }
        let userInfo = response.notification.request.content.userInfo
        guard let carhub = userInfo["carhub"] as? [String: Any],
              (carhub["kind"] as? String) == "coordinator_task",
              let taskIdStr = stringFromAPNs(carhub["task_id"]),
              let taskId = UUID(uuidString: taskIdStr)
        else {
            completion()
            return
        }
        let pushTitle = stringFromAPNs(carhub["task_title"])?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pushNotes = stringFromAPNs(carhub["task_notes"]) ?? ""
        let pushDeadlineISO = stringFromAPNs(carhub["deadline_at"])

        Task {
            do {
                let row = try await TeamCoordinatorTasksService.markAccepted(
                    taskId: taskId,
                    client: SupabaseClientProvider.shared
                )
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .coordinatorTaskAcceptedFromPush,
                        object: nil,
                        userInfo: ["taskId": taskId]
                    )
                }

                let titleRaw = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let calTitle = titleRaw.isEmpty ? (pushTitle.isEmpty ? "Tarea CarHub" : pushTitle) : titleRaw
                let calNotes = row.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? pushNotes
                    : row.body

                let startDate =
                    TeamCoordinatorTasksService.parseDate(row.deadlineAt)
                    ?? parseDeadlineFromPushISO(pushDeadlineISO)

                try await addCalendarEvent(title: calTitle, notes: calNotes, startDate: startDate)
            } catch {
                #if DEBUG
                print("[CarHub] Aceptar tarea desde notificación: \(error.localizedDescription)")
                #endif
            }
            await MainActor.run {
                completion()
            }
        }
    }

    /// APNs / JSON a veces entrega NSString o tipos distintos.
    private static func stringFromAPNs(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let s = value as? NSString { return s as String }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    private static func parseDeadlineFromPushISO(_ iso: String?) -> Date? {
        guard let s = iso?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return TeamCoordinatorTasksService.parseDate(s)
    }

    @MainActor
    private static func addCalendarEvent(title: String, notes: String, startDate: Date?) async throws {
        guard let start = startDate else {
            #if DEBUG
            print("[CarHub] Calendario: sin fecha de plazo (revisar deadline_at en servidor o payload).")
            #endif
            return
        }

        let store = EKEventStore()
        let granted = await requestCalendarAccess(store: store)
        guard granted else {
            #if DEBUG
            print("[CarHub] Calendario: permiso denegado.")
            #endif
            return
        }

        guard let calendar = store.defaultCalendarForNewEvents
            ?? store.calendars(for: .event).first(where: { $0.allowsContentModifications })
        else {
            #if DEBUG
            print("[CarHub] Calendario: no hay calendario editable.")
            #endif
            return
        }

        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.notes = notes
        event.startDate = start
        event.endDate = start.addingTimeInterval(3600)
        event.isAllDay = false
        event.timeZone = .current
        event.addAlarm(EKAlarm(relativeOffset: -3600))
        try store.save(event, span: .thisEvent)
    }

    @MainActor
    private static func requestCalendarAccess(store: EKEventStore) async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                if try await store.requestFullAccessToEvents() { return true }
            } catch {}
            do {
                if try await store.requestWriteOnlyAccessToEvents() { return true }
            } catch {}
            return false
        }
        return await withCheckedContinuation { cont in
            store.requestAccess(to: .event) { ok, _ in
                cont.resume(returning: ok)
            }
        }
    }
}
