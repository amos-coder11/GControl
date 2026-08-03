import Foundation
import UIKit
import UserNotifications

/// Notificaciones locales recurrentes al inicio y fin del horario de la clínica.
enum WorkdayNotificationService {
    private static let idPrefix = "groo.workday.schedule."
    private static let legacyIdPrefix = "drflow.workday.schedule."
    static let activeJornadaId = "groo.workday.active"
    private static let iconCacheFileName = "groo-workday-notification-icon.png"

    private struct DaySchedule {
        let weekday: Int
        let openHour: Int
        let openMinute: Int
        let closeHour: Int
        let closeMinute: Int
    }

    /// Horario clínica: lun–vie 8:00–19:00, sáb 8:30–15:00, domingo cerrado.
    private static let schedules: [DaySchedule] = [
        DaySchedule(weekday: 2, openHour: 8, openMinute: 0, closeHour: 19, closeMinute: 0),
        DaySchedule(weekday: 3, openHour: 8, openMinute: 0, closeHour: 19, closeMinute: 0),
        DaySchedule(weekday: 4, openHour: 8, openMinute: 0, closeHour: 19, closeMinute: 0),
        DaySchedule(weekday: 5, openHour: 8, openMinute: 0, closeHour: 19, closeMinute: 0),
        DaySchedule(weekday: 6, openHour: 8, openMinute: 0, closeHour: 19, closeMinute: 0),
        DaySchedule(weekday: 7, openHour: 8, openMinute: 30, closeHour: 15, closeMinute: 0),
    ]

    static func rescheduleAll() async {
        guard await notificationsAuthorized() else { return }

        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let staleIds = pending.map(\.identifier).filter {
            $0.hasPrefix(idPrefix) || $0.hasPrefix(legacyIdPrefix)
        }
        center.removePendingNotificationRequests(withIdentifiers: staleIds)

        for day in schedules {
            let openTime = formatTime(hour: day.openHour, minute: day.openMinute)
            let closeTime = formatTime(hour: day.closeHour, minute: day.closeMinute)

            await schedule(
                id: "\(idPrefix)open.\(day.weekday)",
                weekday: day.weekday,
                hour: day.openHour,
                minute: day.openMinute,
                title: "Entrada laboral",
                body: "Buenos días. La clínica abre hoy a las \(openTime). Inicia tu jornada."
            )
            await schedule(
                id: "\(idPrefix)close.\(day.weekday)",
                weekday: day.weekday,
                hour: day.closeHour,
                minute: day.closeMinute,
                title: "Salida laboral",
                body: "Fin de jornada. Horario de cierre hoy: \(closeTime)."
            )
        }
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

    // MARK: - Jornada activa (centro de notificaciones)

    private static var lastActiveJornadaBody: String?
    private static var lastActiveJornadaActivity: String?

    /// Publica o actualiza la notificación de jornada en curso (segundo plano).
    /// Omite reescritura si el cuerpo significativo no cambió (evita remove+add cada minuto).
    static func updateActiveJornada(
        elapsedFormatted: String,
        activityTitle: String?,
        startedAt: Date?,
        playsSound: Bool = false
    ) async {
        guard await notificationsAuthorized() else { return }

        var bodyParts = ["Tiempo trabajado: \(elapsedFormatted)"]
        if let activityTitle, !activityTitle.isEmpty {
            bodyParts.append(activityTitle)
        }
        if let startedAt {
            bodyParts.append("Desde \(startedAt.formatted(date: .omitted, time: .shortened))")
        }
        let body = bodyParts.joined(separator: " · ")

        if !playsSound,
           lastActiveJornadaBody == body,
           lastActiveJornadaActivity == activityTitle {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Jornada en curso"
        content.body = body
        content.threadIdentifier = "groo.workday.active"
        content.userInfo = [
            "grooWorkdayActive": true,
            "grooWorkdaySound": playsSound,
        ]
        if playsSound {
            content.sound = .default
        }
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        if let attachment = notificationIconAttachment() {
            content.attachments = [attachment]
        }

        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [activeJornadaId])
        center.removePendingNotificationRequests(withIdentifiers: [activeJornadaId])

        let request = UNNotificationRequest(identifier: activeJornadaId, content: content, trigger: nil)
        try? await center.add(request)
        lastActiveJornadaBody = body
        lastActiveJornadaActivity = activityTitle
    }

    static func clearActiveJornada() async {
        lastActiveJornadaBody = nil
        lastActiveJornadaActivity = nil
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [activeJornadaId])
        center.removePendingNotificationRequests(withIdentifiers: [activeJornadaId])
    }

    static func showJornadaFinished(workedFormatted: String) async {
        guard await notificationsAuthorized() else { return }
        await clearActiveJornada()

        let content = UNMutableNotificationContent()
        content.title = "Jornada finalizada"
        content.body = "Has registrado \(workedFormatted) de trabajo hoy."
        content.sound = .default
        if let attachment = notificationIconAttachment() {
            content.attachments = [attachment]
        }

        let request = UNNotificationRequest(
            identifier: "groo.workday.finished.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func notificationIconAttachment() -> UNNotificationAttachment? {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let cacheDir else { return nil }

        let iconURL = cacheDir.appendingPathComponent(iconCacheFileName)
        if !FileManager.default.fileExists(atPath: iconURL.path) {
            guard let image = UIImage(named: "GrooNotificationIcon"),
                  let resized = resizeForNotification(image, maxSide: 256),
                  let data = resized.pngData()
            else { return nil }
            try? data.write(to: iconURL, options: .atomic)
        }

        return try? UNNotificationAttachment(
            identifier: "groo-workday-icon",
            url: iconURL,
            options: [UNNotificationAttachmentOptionsTypeHintKey: "public.png"]
        )
    }

    private static func resizeForNotification(_ image: UIImage, maxSide: CGFloat) -> UIImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(maxSide / size.width, maxSide / size.height, 1)
        guard scale < 1 else { return image }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private static func formatTime(hour: Int, minute: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        guard let date = Calendar.current.date(from: components) else {
            return String(format: "%d:%02d", hour, minute)
        }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private static func notificationsAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral
    }
}
