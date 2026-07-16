import Foundation
import UIKit
import UserNotifications

extension Notification.Name {
    static let grooOpenRemindersTab = Notification.Name("Groo.openRemindersTab")
}

/// Parses relative deadlines and appointment mentions in Spanish/English.
enum GrooReminderTimeParser {
    private static let relativePattern =
        #"(?:en\s+|in\s+|for\s+)?(\d+)\s*(segundos?|seconds?|secs?|s|minutos?|minutes?|mins?|m|horas?|hours?|hrs?|h|d[ií]as?|days?|d)\b"#

    private static let reminderIntentHints = [
        "remind", "reminder", "recordatorio", "recuérdame", "recuerdame",
        "recuerda", "alert me", "notify me", "avísame", "avisame",
    ]

    private static let eventHints = [
        "cita", "appointment", "meeting", "reunión", "reunion",
        "entrevista", "interview", "review", "revisión", "revision",
    ]

    static func isReminderRequest(_ text: String) -> Bool {
        guard parseDueDate(from: text) != nil else { return false }
        let lower = text.lowercased()
        if reminderIntentHints.contains(where: { lower.contains($0) }) { return true }
        return mentionsScheduledEvent(lower)
    }

    static func parseDueDate(from text: String) -> Date? {
        if let relative = parseRelativeDueDate(from: text) {
            return relative
        }
        return parseNaturalDueDate(from: text)
    }

    static func suggestedTitle(from text: String) -> String {
        let lower = text.lowercased()
        if matchesWord("reunión", "reunion", "meeting", in: lower) { return "Meeting" }
        if matchesWord("entrevista", "interview", in: lower) { return "Interview" }
        if matchesWord("cita", "appointment", in: lower) { return "Appointment" }
        if matchesWord("revisión", "revision", "review", in: lower) { return "Review" }
        return "GROO reminder"
    }

    static func relativeSpanDescription(from text: String) -> String? {
        guard parseRelativeDueDate(from: text) != nil else { return nil }
        let lower = text.lowercased()
        guard let regex = try? NSRegularExpression(pattern: relativePattern, options: .caseInsensitive) else {
            return nil
        }
        let nsRange = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        guard let match = regex.firstMatch(in: lower, options: [], range: nsRange),
              match.numberOfRanges >= 3,
              let numRange = Range(match.range(at: 1), in: lower),
              let unitRange = Range(match.range(at: 2), in: lower),
              let amount = Int(lower[numRange])
        else { return nil }

        let unit = String(lower[unitRange])
        let label = spanLabel(for: amount, unit: unit)
        return "\(amount) \(label)"
    }

    static func cannedAssistantReply(title: String, span: String?, dueAt: Date) -> String {
        let clock = dueAt.formatted(date: .abbreviated, time: .shortened)
        if let span {
            return """
            Done. I'll remind you about «\(title)» in \(span).

            I'll notify you at \(clock). You'll also see it in Reminders.
            """
        }
        return """
        Done. I'll remind you about «\(title)» on \(clock).

        I'll send you a notification then. You'll also see it in Reminders.
        """
    }

    // MARK: - Private

    private static func mentionsScheduledEvent(_ lower: String) -> Bool {
        eventHints.contains { hint in
            if hint == "cita" {
                return lower.range(of: #"\bcita\b"#, options: .regularExpression) != nil
            }
            return lower.contains(hint)
        }
    }

    private static func matchesWord(_ words: String..., in lower: String) -> Bool {
        words.contains { word in
            if word == "cita" {
                return lower.range(of: #"\bcita\b"#, options: .regularExpression) != nil
            }
            return lower.contains(word)
        }
    }

    private static func parseRelativeDueDate(from text: String) -> Date? {
        let lower = text.lowercased()
        guard let regex = try? NSRegularExpression(pattern: relativePattern, options: .caseInsensitive) else {
            return nil
        }
        let nsRange = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        guard let match = regex.firstMatch(in: lower, options: [], range: nsRange),
              match.numberOfRanges >= 3,
              let numRange = Range(match.range(at: 1), in: lower),
              let unitRange = Range(match.range(at: 2), in: lower),
              let amount = Int(lower[numRange])
        else { return nil }

        let unit = String(lower[unitRange])
        let interval = seconds(for: amount, unit: unit)
        guard interval > 0 else { return nil }
        return Date().addingTimeInterval(interval)
    }

    /// «tomorrow at 3pm», «mañana a las 10», etc. via NSDataDetector.
    private static func parseNaturalDueDate(from text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector.matches(in: text, options: [], range: nsRange)
        return matches.compactMap(\.date).first { $0 > Date() }
    }

    private static func spanLabel(for amount: Int, unit: String) -> String {
        if unit.hasPrefix("seg") || unit.hasPrefix("sec") || unit == "s" {
            return amount == 1 ? "second" : "seconds"
        }
        if unit.hasPrefix("min") || unit == "m" {
            return amount == 1 ? "minute" : "minutes"
        }
        if unit.hasPrefix("hor") || unit.hasPrefix("hr") || unit == "h" {
            return amount == 1 ? "hour" : "hours"
        }
        return amount == 1 ? "day" : "days"
    }

    private static func seconds(for amount: Int, unit: String) -> TimeInterval {
        if unit.hasPrefix("seg") || unit.hasPrefix("sec") || unit == "s" {
            return TimeInterval(amount)
        }
        if unit.hasPrefix("min") || unit == "m" {
            return TimeInterval(amount * 60)
        }
        if unit.hasPrefix("hor") || unit.hasPrefix("hr") || unit == "h" {
            return TimeInterval(amount * 3600)
        }
        if unit.hasPrefix("d") {
            return TimeInterval(amount * 86_400)
        }
        return 0
    }
}

/// Local notifications for reminders created from GROO chat.
enum GrooReminderNotificationService {
    private static let iconCacheFileName = "groo-reminder-notification-icon.png"
    private static let maxIntervalTrigger: TimeInterval = 604_800 // 1 week (iOS limit)

    static func notificationId(for reminderId: UUID) -> String {
        "groo.reminder.\(reminderId.uuidString.lowercased())"
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
            do {
                try data.write(to: iconURL, options: .atomic)
            } catch {
                return nil
            }
        }

        return try? UNNotificationAttachment(
            identifier: "groo-icon",
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

    static func ensureAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }

    static func schedule(reminder: GrooReminder) async {
        guard !reminder.isDone else { return }
        let interval = reminder.dueAt.timeIntervalSinceNow
        guard interval > 0 else { return }
        guard await ensureAuthorization() else { return }

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.note.isEmpty ? "It's time for your reminder." : reminder.note
        content.sound = .default
        content.userInfo = ["grooReminderId": reminder.id.uuidString]

        let trigger = makeTrigger(for: reminder.dueAt, interval: interval)
        let id = notificationId(for: reminder.id)

        if let attachment = notificationIconAttachment() {
            content.attachments = [attachment]
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            do {
                try await UNUserNotificationCenter.current().add(request)
                return
            } catch {
                #if DEBUG
                print("[GROO Reminder] Notification with attachment failed: \(error.localizedDescription)")
                #endif
                content.attachments = []
            }
        }

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            #if DEBUG
            print("[GROO Reminder] Notification schedule failed: \(error.localizedDescription)")
            #endif
        }
    }

    private static func makeTrigger(for dueAt: Date, interval: TimeInterval) -> UNNotificationTrigger {
        if interval <= maxIntervalTrigger {
            return UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        }
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: dueAt
        )
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    static func cancel(reminderId: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationId(for: reminderId)]
        )
    }

    static func rescheduleAll(reminders: [GrooReminder]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let grooIds = pending
            .map(\.identifier)
            .filter { $0.hasPrefix("groo.reminder.") }
        center.removePendingNotificationRequests(withIdentifiers: grooIds)

        for reminder in reminders where !reminder.isDone && reminder.dueAt > Date() {
            await schedule(reminder: reminder)
        }
    }
}
