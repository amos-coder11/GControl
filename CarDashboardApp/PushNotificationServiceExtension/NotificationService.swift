import UserNotifications
import UniformTypeIdentifiers

/// Descarga la foto del contacto / remitente y la adjunta a la notificación
/// (requiere `mutable-content: 1` + `drflow.avatar_url` o `drflow.image_url`).
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?
    private var downloadTask: URLSessionDownloadTask?

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

        guard let imageURL = Self.imageURL(from: bestAttemptContent.userInfo) else {
            contentHandler(bestAttemptContent)
            return
        }

        downloadTask = URLSession.shared.downloadTask(with: imageURL) { [weak self] localURL, response, _ in
            guard let self, let contentHandler = self.contentHandler, let best = self.bestAttemptContent else { return }
            defer { contentHandler(best) }

            guard let localURL else { return }

            let mime = (response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Content-Type")?
                .lowercased() ?? ""
            let (fileExtension, typeHint) = Self.fileType(url: imageURL, mime: mime)

            let dest = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString + "." + fileExtension)
            try? FileManager.default.removeItem(at: dest)

            do {
                try FileManager.default.copyItem(at: localURL, to: dest)
                var options: [String: Any] = [:]
                if let typeHint {
                    options[UNNotificationAttachmentOptionsTypeHintKey] = typeHint
                }
                let attachment = try UNNotificationAttachment(
                    identifier: "notification-image",
                    url: dest,
                    options: options.isEmpty ? nil : options
                )
                best.attachments = [attachment]
            } catch {
                // Sin adjunto si falla la descarga/copia
            }
        }
        downloadTask?.resume()
    }

    override func serviceExtensionTimeWillExpire() {
        downloadTask?.cancel()
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    /// Prioriza media del mensaje; si no hay, usa avatar del contacto/remitente.
    private static func imageURL(from userInfo: [AnyHashable: Any]) -> URL? {
        let drflow = userInfo["drflow"] as? [String: Any]
        let candidates: [String?] = [
            drflow?["image_url"] as? String,
            drflow?["media_url"] as? String,
            drflow?["avatar_url"] as? String,
            userInfo["image_url"] as? String,
            userInfo["avatar_url"] as? String,
        ]
        for raw in candidates {
            guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty,
                  let url = URL(string: s),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https"
            else { continue }
            return url
        }
        return nil
    }

    private static func fileType(url: URL, mime: String) -> (String, String?) {
        let ext = url.pathExtension.lowercased()
        if mime.contains("png") || ext == "png" {
            return ("png", UTType.png.identifier)
        }
        if mime.contains("webp") || ext == "webp" {
            return ("webp", UTType.webP.identifier)
        }
        if mime.contains("gif") || ext == "gif" {
            return ("gif", UTType.gif.identifier)
        }
        return ("jpg", UTType.jpeg.identifier)
    }
}
