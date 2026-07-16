import UserNotifications

/// Añade este archivo a un target **Notification Service Extension** en Xcode
/// (File → New → Target → Notification Service Extension) con bundle id
/// `com.groo.app.PushNotificationServiceExtension` y embútelo en la app principal.
/// La push debe llevar `mutable-content: 1` (ya lo envía la Edge Function `send-message-push`).
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        guard let bestAttemptContent else {
            contentHandler(request.content)
            return
        }

        let userInfo = bestAttemptContent.userInfo
        guard let drflow = userInfo["drflow"] as? [String: Any],
              let urlString = drflow["avatar_url"] as? String,
              !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: urlString)
        else {
            contentHandler(bestAttemptContent)
            return
        }

        let task = URLSession.shared.downloadTask(with: url) { [weak self] localURL, _, _ in
            guard let self, let contentHandler = self.contentHandler, let best = self.bestAttemptContent else { return }
            defer { contentHandler(best) }

            guard let localURL else { return }

            let ext = url.pathExtension.lowercased()
            let fileExtension: String
            switch ext {
            case "jpg", "jpeg": fileExtension = "jpg"
            case "png", "webp": fileExtension = "png"
            default: fileExtension = "jpg"
            }

            let dest = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString + "." + fileExtension)
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.copyItem(at: localURL, to: dest)
                let attachment = try UNNotificationAttachment(
                    identifier: "avatar",
                    url: dest,
                    options: [UNNotificationAttachmentOptionsTypeHintKey: "public.jpeg"]
                )
                best.attachments = [attachment]
            } catch {
                // Sin adjunto si falla la copia o el tipo
            }
        }
        task.resume()
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
}
