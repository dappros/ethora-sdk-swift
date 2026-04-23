//
//  UseLogout.swift
//  XMPPChatCore
//
//  Единый Logout-флоу: разрыв XMPP, отписка от push/mucsub,
//  очистка кэшей и токенов. Идемпотентен — безопасно дёргать
//  даже когда юзер уже разлогинен.
//

import Foundation

@MainActor
public final class LogoutManager {
    public static let shared = LogoutManager()
    private init() {}

    /// Опции logout. Дефолт — полный logout с сохранением `ChatConfig`
    /// (baseUrl, appId, стилинг и т.п.) — обычно хостинг-приложение хочет
    /// сохранить свои настройки после logout.
    public struct Options: Sendable {
        /// Разорвать XMPP-соединение.
        public var disconnectXMPP: Bool
        /// Сбросить push (FCM-токен, mucsub room subscriptions, список подписанных комнат в UserDefaults).
        public var resetPush: Bool
        /// Обнулить токены и текущего юзера (UserStore + кэш сообщений).
        public var clearUser: Bool
        /// Очистить комнаты, pending-heap, unread-счётчики, pending push JID.
        public var clearCaches: Bool
        /// Сбросить `ChatConfig` к дефолту. Обычно НЕ нужно — хостинг-приложение
        /// при следующем логине переиспользует те же API/XMPP настройки.
        public var resetConfig: Bool

        public init(
            disconnectXMPP: Bool = true,
            resetPush: Bool = true,
            clearUser: Bool = true,
            clearCaches: Bool = true,
            resetConfig: Bool = false
        ) {
            self.disconnectXMPP = disconnectXMPP
            self.resetPush = resetPush
            self.clearUser = clearUser
            self.clearCaches = clearCaches
            self.resetConfig = resetConfig
        }

        public static let `default` = Options()
    }

    /// Полный logout.
    ///
    /// Порядок важен: push/mucsub сбрасываются до разрыва XMPP (пока ещё есть
    /// живой stream), затем отключаем XMPP, затем чистим stores и persistence.
    /// - Parameters:
    ///   - client: конкретный `XMPPClient`. Если nil — берём из `ClientRegistry`.
    ///   - options: тонкая настройка, что именно чистить.
    public func logout(
        client: XMPPClient? = nil,
        options: Options = .default
    ) async {
        let target = client ?? ClientRegistry.shared.getGlobalXMPPClient()
        print("[Logout] start — disconnectXMPP=\(options.disconnectXMPP) resetPush=\(options.resetPush) clearUser=\(options.clearUser) clearCaches=\(options.clearCaches) resetConfig=\(options.resetConfig)")

        // 1. Push: обнулить FCM-token, ссылки и выбросить кэш подписок
        //    mucsub в PushSubscriptionService. Делается до disconnect, чтобы
        //    при необходимости можно было дослать stop-subscribe через stream.
        if options.resetPush {
            await PushNotificationManager.shared.reset()
        }

        // 2. XMPP disconnect — graceful close стрима.
        if options.disconnectXMPP, let target {
            await target.disconnect()
        }

        // 3. Отпустить глобальную ссылку на клиент — следующий login
        //    создаст новый экземпляр `XMPPClient` и зарегистрирует его заново.
        ClientRegistry.shared.setGlobalXMPPClient(nil)

        // 4. Кэши комнат / сообщений / pending / notifications.
        //    `MessageHeapState` — это ObservableObject, который хостинг-код
        //    создаёт сам; у нас нет global handle на него. Экземпляр умрёт
        //    вместе с его view-model'ю при ререндере после смены isAuthenticated.
        if options.clearCaches {
            RoomStore.shared.clearAll()
            MessageCache.shared.clearAll()
            // Unread/last-read ключи ведутся в UseUnreadMessagesCounter напрямую
            // через UserDefaults — очищаем здесь, чтобы не висели между сессиями
            // двух разных юзеров.
            UserDefaults.standard.removeObject(forKey: "ethora_unread_counts")
            UserDefaults.standard.removeObject(forKey: "ethora_last_read")
            PendingNotificationJidStore.clearPendingJid()
        }

        // 5. Токены и user data. UserStore.clearUser() сам вызывает
        //    MessageCache.clearAll() — не страшно, что в шаге 4 мы его
        //    уже очистили.
        if options.clearUser {
            UserStore.shared.clearUser()
        }

        // 6. Optional: сброс конфига. По умолчанию выключено.
        if options.resetConfig {
            ConfigStore.shared.reset()
        }

        print("[Logout] complete")
    }

    // MARK: - Legacy completion-based API

    /// Callback-обёртка над `logout(client:options:)` — для хостинг-кода,
    /// который не хочет async/await.
    public func logout(
        client: XMPPClient?,
        onCompletion: @escaping () -> Void
    ) {
        Task { @MainActor in
            await logout(client: client, options: .default)
            onCompletion()
        }
    }

    /// Спрашивает подтверждение и, если confirmed, выполняет полный logout.
    public func logoutWithConfirmation(
        client: XMPPClient?,
        showConfirmation: @escaping (@escaping (Bool) -> Void) -> Void,
        onCompletion: @escaping () -> Void
    ) {
        showConfirmation { confirmed in
            guard confirmed else { return }
            self.logout(client: client, onCompletion: onCompletion)
        }
    }
}
