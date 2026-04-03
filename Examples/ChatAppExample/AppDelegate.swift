import UIKit
import UserNotifications
import XMPPChatCore

#if canImport(FirebaseCore)
import FirebaseCore
#endif

#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

final class AppDelegate: NSObject, UIApplicationDelegate {
    #if canImport(FirebaseMessaging)
    private func fetchFCMToken(reason: String) {
        Messaging.messaging().token { token, error in
            if let error {
                print("[Push] FCM token fetch failed (\(reason)): \(error.localizedDescription)")
                return
            }
            guard let token, !token.isEmpty else {
                print("[Push] FCM token empty (\(reason))")
                return
            }
            print("[Push] FCM token received: \(token.prefix(16))... (\(reason))")
            Task { @MainActor in
                PushNotificationManager.shared.updateFCMToken(token)
            }
        }
    }
    #endif

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        print("[Push] app didFinishLaunching")
        #if canImport(FirebaseCore)
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        if let configuredBundleID = FirebaseApp.app()?.options.bundleID {
            let runtimeBundleID = Bundle.main.bundleIdentifier ?? "nil"
            print("[Push] Firebase bundleID config=\(configuredBundleID) runtime=\(runtimeBundleID)")
        }
        #endif

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error {
                print("[Push] authorization error: \(error.localizedDescription)")
            } else {
                print("[Push] authorization granted: \(granted)")
            }
        }
        application.registerForRemoteNotifications()

        #if canImport(FirebaseMessaging)
        Messaging.messaging().delegate = self
        Messaging.messaging().isAutoInitEnabled = true
        fetchFCMToken(reason: "didFinishLaunching")
        #endif

        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        print("[Push] APNs token received, size=\(deviceToken.count)")
        #if canImport(FirebaseMessaging)
        Messaging.messaging().apnsToken = deviceToken
        fetchFCMToken(reason: "didRegisterForRemoteNotifications")
        #endif
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[Push] APNs registration failed: \(error.localizedDescription)")
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        if let jid = RemoteNotificationPayload.roomJid(from: userInfo) {
            PendingNotificationJidStore.store(jid: jid)
        }
        completionHandler([.banner, .badge, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let jid = RemoteNotificationPayload.roomJid(from: userInfo) {
            PendingNotificationJidStore.store(jid: jid)
        }
        completionHandler()
    }
}

#if canImport(FirebaseMessaging)
extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken, !fcmToken.isEmpty else { return }
        print("[Push] FCM token received: \(fcmToken.prefix(16))... (delegate)")
        Task { @MainActor in
            PushNotificationManager.shared.updateFCMToken(fcmToken)
        }
    }

    /// Foreground data messages (FCM) — mirror RN background handler storing `data.jid`.
    func messaging(_ messaging: Messaging, didReceive remoteMessage: MessagingRemoteMessage) {
        let flat = remoteMessage.appData as [AnyHashable: Any]
        if let jid = RemoteNotificationPayload.roomJid(from: flat) {
            PendingNotificationJidStore.store(jid: jid)
        }
    }
}
#endif

