import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        MessageNotificationService.registerCategories()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        RemotePushRegistration.storeDeviceTokenFromAPNs(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("[Drflow APNs] Registro fallido: \(error.localizedDescription)")
        #endif
    }

    /// Notificación entrante con la app en primer plano.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Segundo plano / data-only: iOS puede despertar la app brevemente si el payload lleva `content-available: 1`.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        NotificationCenter.default.post(
            name: .refreshInboxFromPush,
            object: nil,
            userInfo: userInfo
        )
        completionHandler(.newData)
    }

    /// Acciones de notificación (Aceptar tarea Viera) o abrir chat / recordatorios al pulsar el aviso.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == DrflowNotificationCategories.coordinatorTaskAcceptAction {
            CoordinatorTaskPushActionHandler.handleAcceptIfNeeded(response: response, completion: completionHandler)
            return
        }

        let userInfo = response.notification.request.content.userInfo
        if userInfo["grooReminderId"] != nil {
            NotificationCenter.default.post(name: .grooOpenRemindersTab, object: nil)
            completionHandler()
            return
        }

        MessageNotificationService.postOpenChatRouting(from: response)
        completionHandler()
    }
}
