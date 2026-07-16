import Foundation
import UserNotifications

/// Notificaciones locales recurrentes al inicio y fin del horario del concesionario.
enum WorkdayNotificationService {
    private static let idPrefix = "drflow.workday.schedule."

    static func rescheduleAll() async {
        guard await notificationsAuthorized() else { return }

        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let staleIds = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: staleIds)

        // Lunes a viernes (weekday 2…6 en Calendar)
        for weekday in 2 ... 6 {
            await schedule(
                id: "\(idPrefix)open.\(weekday)",
                weekday: weekday,
                hour: 10,
                minute: 0,
                title: "Inicio de jornada",
                body: "El concesionario abre a las 10:00 h. Inicia tu jornada laboral."
            )
            await schedule(
                id: "\(idPrefix)close.\(weekday)",
                weekday: weekday,
                hour: 19,
                minute: 30,
                title: "Fin de jornada",
                body: "Termina tu jornada laboral. Horario hasta las 19:30 h."
            )
        }

        // Sábado
        await schedule(
            id: "\(idPrefix)open.7",
            weekday: 7,
            hour: 11,
            minute: 0,
            title: "Inicio de jornada",
            body: "El concesionario abre a las 11:00 h. Inicia tu jornada laboral."
        )
        await schedule(
            id: "\(idPrefix)close.7",
            weekday: 7,
            hour: 14,
            minute: 0,
            title: "Fin de jornada",
            body: "Termina tu jornada laboral. Horario hasta las 14:00 h."
        )
    }

    private static func schedule(
        id: String,
        weekday: Int,
        hour: Int,
        minute: Int,
        title: String,
        body: String
    ) async {
        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = minute

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func notificationsAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }
}
