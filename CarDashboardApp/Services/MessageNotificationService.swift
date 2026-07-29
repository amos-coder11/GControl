import Foundation
import UIKit
import UserNotifications

extension Notification.Name {
    /// Abrir un hilo de chat tras pulsar una notificación (payload en `userInfo`).
    static let openChatFromPush = Notification.Name("Drflow.openChatFromPush")
    /// Refrescar bandeja Instagram tras push remota (app en segundo plano).
    static let refreshInboxFromPush = Notification.Name("Drflow.refreshInboxFromPush")
}

/// Avisos locales de nuevos mensajes CRM y enrutamiento al pulsar push remota/local.
enum MessageNotificationService {
    static let leadCategoryId = "DRFLOW_LEAD_MESSAGE"

    static func registerCategories() {
        let accept = UNNotificationAction(
            identifier: DrflowNotificationCategories.coordinatorTaskAcceptAction,
            title: "Aceptar",
            options: [.foreground]
        )
        let coordinatorCategory = UNNotificationCategory(
            identifier: DrflowNotificationCategories.coordinatorTask,
            actions: [accept],
            intentIdentifiers: [],
            options: []
        )
        let leadCategory = UNNotificationCategory(
            identifier: leadCategoryId,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([
            coordinatorCategory,
            leadCategory,
        ])
    }

    /// Compara conversaciones CRM antes/después del refresh y avisa si hay mensaje nuevo del cliente.
    @MainActor
    static func notifyNewCrmMessages(
        previous: [UUID: CrmLeadSnapshot],
        current: [ChatThread],
        activeThreadId: UUID?,
        accessToken: String? = nil
    ) {
        Task {
            guard await notificationsAuthorized() else { return }

            for thread in current where thread.kind == .lead {
                if thread.id == activeThreadId { continue }

                let preview = thread.preview.trimmingCharacters(in: .whitespacesAndNewlines)
                let unread = thread.unread ?? 0
                guard unread > 0, !preview.isEmpty else { continue }

                let snap = previous[thread.id]
                let isNew: Bool
                if let snap {
                    isNew = unread > snap.unread
                } else {
                    isNew = true
                }

                guard isNew else { continue }
                await scheduleLeadNotification(
                    thread: thread,
                    body: preview,
                    accessToken: accessToken
                )
            }
        }
    }

    @MainActor
    private static func scheduleLeadNotification(
        thread: ChatThread,
        body: String,
        accessToken: String?
    ) async {
        let content = UNMutableNotificationContent()
        content.title = leadNotificationTitle(for: thread)
        content.body = truncate(body, max: 180)
        content.sound = .default
        content.categoryIdentifier = leadCategoryId
        content.userInfo = [
            "drflow": [
                "kind": "crm_lead",
                "thread_id": thread.id.uuidString,
            ],
        ]

        if let attachment = await contactAvatarAttachment(for: thread, accessToken: accessToken) {
            content.attachments = [attachment]
        }

        let id = "crm-\(thread.id.uuidString)-\(Int(Date().timeIntervalSince1970))"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func contactAvatarAttachment(
        for thread: ChatThread,
        accessToken: String?
    ) async -> UNNotificationAttachment? {
        guard let url = thread.avatarCarURL else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        if let token = accessToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200 ... 299).contains(http.statusCode),
              let image = UIImage(data: data),
              let resized = resizeForNotification(image, maxSide: 256),
              let png = resized.pngData()
        else { return nil }

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let cacheDir else { return nil }

        let fileURL = cacheDir.appendingPathComponent("crm-avatar-\(thread.id.uuidString).png")
        do {
            try png.write(to: fileURL, options: .atomic)
        } catch {
            return nil
        }

        return try? UNNotificationAttachment(
            identifier: "contact-avatar",
            url: fileURL,
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

    private static func leadNotificationTitle(for thread: ChatThread) -> String {
        switch thread.socialSource {
        case .whatsApp:
            return thread.title
        case .instagram:
            return thread.title
        default:
            return thread.title
        }
    }

    private static func truncate(_ text: String, max: Int) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > max else { return t }
        return String(t.prefix(max - 1)) + "…"
    }

    private static func notificationsAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    /// Pulsa en notificación (local o APNs): publica ruta para abrir el chat.
    static func postOpenChatRouting(from response: UNNotificationResponse) {
        guard let routing = parseRouting(from: response.notification.request.content.userInfo) else { return }
        NotificationCenter.default.post(
            name: .openChatFromPush,
            object: nil,
            userInfo: routing
        )
    }

    /// Aplica la ruta en la UI principal (MainTabView).
    @MainActor
    static func applyOpenChatRouting(
        _ userInfo: [AnyHashable: Any],
        chatInbox: ChatInboxStore,
        tabRouter: MainTabRouter,
        chatNav: ChatNavigationCoordinator
    ) {
        guard let kind = userInfo["kind"] as? String else { return }

        switch kind {
        case "crm_lead":
            guard let idStr = userInfo["thread_id"] as? String,
                  let threadId = UUID(uuidString: idStr),
                  chatInbox.liveThreads.contains(where: { $0.id == threadId })
            else { return }
            tabRouter.selected = .chat

        case "dm":
            guard let senderStr = userInfo["sender_id"] as? String,
                  let senderId = UUID(uuidString: senderStr),
                  chatInbox.teamDirectChatThreads.first(where: { $0.peerUserId == senderId }) != nil
            else { return }
            tabRouter.selected = .chat

        case "group":
            guard chatInbox.teamGroupChatThread != nil else { return }
            tabRouter.selected = .chat

        default:
            break
        }
    }

    private static func parseRouting(from userInfo: [AnyHashable: Any]) -> [String: String]? {
        guard let drflow = userInfo["drflow"] as? [String: Any],
              let kind = stringValue(drflow["kind"])
        else { return nil }

        switch kind {
        case "crm_lead":
            guard let threadId = stringValue(drflow["thread_id"]) else { return nil }
            return ["kind": kind, "thread_id": threadId]
        case "dm":
            guard let senderId = stringValue(drflow["sender_id"]) else { return nil }
            return ["kind": kind, "sender_id": senderId]
        case "group":
            return ["kind": kind]
        default:
            return nil
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let s = value as? NSString { return s as String }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }
}

/// Snapshot ligero para detectar mensajes CRM nuevos entre refrescos.
struct CrmLeadSnapshot: Equatable {
    let preview: String
    let unread: Int
}
