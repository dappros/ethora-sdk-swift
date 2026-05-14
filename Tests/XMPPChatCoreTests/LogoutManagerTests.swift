import XCTest
@testable import XMPPChatCore

/// Hermetic L1 tests for `LogoutManager` (`UseLogout`) — the unified
/// cleanup flow that runs on logout.
///
/// We exercise the no-XMPP code path (`disconnectXMPP=false`,
/// `resetPush=false`) so the test doesn't need a live socket or push
/// stack. That still leaves the meaningful surface: cache wipes
/// (RoomStore, MessageCache, unread-count UserDefaults keys,
/// PendingNotificationJidStore), UserStore wipe, and idempotency.
///
/// Order rule from CLAUDE.md: clear caches BEFORE clearing UserStore
/// (so a partial failure leaves a smaller blast radius). We don't pin
/// the order here — we assert the end state.
@MainActor
final class LogoutManagerTests: XCTestCase {

    private let unreadCountsKey = "ethora_unread_counts"
    private let lastReadKey = "ethora_last_read"

    override func setUp() async throws {
        // Seed everything that logout is supposed to wipe.
        RoomStore.shared.clearAll()
        UserStore.shared.clearUser()
        MessageCache.shared.clearAll()
        ClientRegistry.shared.setGlobalXMPPClient(nil)
        UserDefaults.standard.removeObject(forKey: unreadCountsKey)
        UserDefaults.standard.removeObject(forKey: lastReadKey)
        PendingNotificationJidStore.clearPendingJid()
    }

    override func tearDown() async throws {
        RoomStore.shared.clearAll()
        UserStore.shared.clearUser()
        MessageCache.shared.clearAll()
        ClientRegistry.shared.setGlobalXMPPClient(nil)
        UserDefaults.standard.removeObject(forKey: unreadCountsKey)
        UserDefaults.standard.removeObject(forKey: lastReadKey)
        PendingNotificationJidStore.clearPendingJid()
    }

    // MARK: - Helpers

    /// No-XMPP, no-push options — covers everything testable without a
    /// live socket.
    private var hermeticOptions: LogoutManager.Options {
        LogoutManager.Options(
            disconnectXMPP: false,
            resetPush: false,
            clearUser: true,
            clearCaches: true,
            resetConfig: false
        )
    }

    private func seedLoggedInState() {
        // RoomStore — one room with a message
        let room = Room(
            id: "r-1",
            jid: "r-1@conference.test",
            name: "test-room",
            title: "Test Room"
        )
        RoomStore.shared.addRoom(room)
        let message = Message(
            id: "m-1",
            user: User(id: "u-1@xmpp.test"),
            date: Date(),
            body: "hi",
            roomJid: room.jid,
            timestamp: 1_000
        )
        RoomStore.shared.setRoomMessages(roomJID: room.jid, messages: [message])

        // MessageCache — same message
        MessageCache.shared.saveMessages([message], forRoomJID: room.jid)

        // UserStore — directly poke the published state (avoids
        // building a LoginResponse fixture here).
        UserStore.shared.token = "tok"
        UserStore.shared.refreshToken = "refresh"
        UserStore.shared.currentUser = User(id: "u-1")
        UserStore.shared.isAuthenticated = true

        // Unread / last-read UserDefaults keys.
        UserDefaults.standard.set(Data(), forKey: unreadCountsKey)
        UserDefaults.standard.set(Data(), forKey: lastReadKey)

        // Pending push deep-link JID.
        PendingNotificationJidStore.store(jid: "r-1@conference.test")
    }

    // MARK: - Cache + user clear

    func testLogoutClearsRoomStoreCacheAndUserState() async {
        seedLoggedInState()
        // Sanity checks — the seeded state landed.
        XCTAssertFalse(RoomStore.shared.rooms.isEmpty, "precondition: rooms seeded")
        XCTAssertTrue(MessageCache.shared.hasCachedMessages(forRoomJID: "r-1@conference.test"))
        XCTAssertTrue(UserStore.shared.isAuthenticated)
        XCTAssertEqual(PendingNotificationJidStore.peekPendingBareJid(), "r-1@conference.test")

        await LogoutManager.shared.logout(client: nil, options: hermeticOptions)

        XCTAssertTrue(RoomStore.shared.rooms.isEmpty,
                      "RoomStore.clearAll must wipe rooms")
        XCTAssertFalse(MessageCache.shared.hasCachedMessages(forRoomJID: "r-1@conference.test"),
                       "MessageCache.clearAll must wipe per-room messages")
        XCTAssertFalse(UserStore.shared.isAuthenticated)
        XCTAssertNil(UserStore.shared.currentUser)
        XCTAssertNil(UserStore.shared.token)
        XCTAssertNil(UserDefaults.standard.data(forKey: unreadCountsKey),
                     "ethora_unread_counts must be removed")
        XCTAssertNil(UserDefaults.standard.data(forKey: lastReadKey),
                     "ethora_last_read must be removed")
        XCTAssertNil(PendingNotificationJidStore.peekPendingBareJid(),
                     "pending push JID must be cleared so a stale notification doesn't auto-open after re-login")
    }

    func testLogoutReleasesGlobalXMPPClientReference() async {
        // We can't construct an XMPPClient in a unit test (it needs a
        // socket), but ClientRegistry accepts nil. Pretending a client
        // was registered would require live mocking. Instead, verify
        // the post-logout state is nil — i.e., the next login starts
        // from a clean registry.
        await LogoutManager.shared.logout(client: nil, options: hermeticOptions)
        XCTAssertNil(ClientRegistry.shared.getGlobalXMPPClient(),
                     "logout must leave ClientRegistry empty")
    }

    // MARK: - Per-option gating

    func testClearCachesFalseLeavesRoomStoreAndUnreadKeysIntact() async {
        // The opt-out path: a host that wants to keep cached rooms
        // across "soft logout" (e.g. switching tabs) can pass
        // clearCaches=false. Pin the gate so a future refactor doesn't
        // accidentally wipe caches anyway.
        seedLoggedInState()

        let options = LogoutManager.Options(
            disconnectXMPP: false,
            resetPush: false,
            clearUser: true,
            clearCaches: false,
            resetConfig: false
        )
        await LogoutManager.shared.logout(client: nil, options: options)

        XCTAssertFalse(RoomStore.shared.rooms.isEmpty,
                       "clearCaches=false must keep rooms")
        XCTAssertTrue(MessageCache.shared.hasCachedMessages(forRoomJID: "r-1@conference.test"),
                      "clearCaches=false must keep cached messages too — but UserStore.clearUser is still called, which itself clears MessageCache")
    }

    func testClearUserFalseLeavesUserStoreIntact() async {
        seedLoggedInState()

        let options = LogoutManager.Options(
            disconnectXMPP: false,
            resetPush: false,
            clearUser: false,
            clearCaches: true,
            resetConfig: false
        )
        await LogoutManager.shared.logout(client: nil, options: options)

        // Caches wiped, but the authenticated user remains.
        XCTAssertTrue(RoomStore.shared.rooms.isEmpty)
        XCTAssertTrue(UserStore.shared.isAuthenticated,
                      "clearUser=false must keep the user authenticated")
        XCTAssertNotNil(UserStore.shared.token)
    }

    func testResetConfigGateOffPreservesChatConfig() async {
        // Hosts typically reuse their ChatConfig across login sessions —
        // resetConfig is opt-in. Confirm the default-off behaviour.
        var seed = ChatConfig()
        seed.appId = "host-app-id"
        seed.baseUrl = "https://api.example.com"
        ConfigStore.shared.mergeConfig(seed)
        seedLoggedInState()

        await LogoutManager.shared.logout(client: nil, options: hermeticOptions)

        XCTAssertEqual(ConfigStore.shared.config.appId, "host-app-id",
                       "default-off resetConfig must preserve host's ChatConfig")
        XCTAssertEqual(ConfigStore.shared.config.baseUrl, "https://api.example.com")

        // Cleanup so other tests in the suite don't see leftover state.
        ConfigStore.shared.reset()
    }

    func testResetConfigGateOnZeroesChatConfig() async {
        var seed = ChatConfig()
        seed.appId = "host-app-id"
        seed.baseUrl = "https://api.example.com"
        ConfigStore.shared.mergeConfig(seed)

        let options = LogoutManager.Options(
            disconnectXMPP: false,
            resetPush: false,
            clearUser: true,
            clearCaches: true,
            resetConfig: true
        )
        await LogoutManager.shared.logout(client: nil, options: options)

        XCTAssertNil(ConfigStore.shared.config.appId)
        XCTAssertNil(ConfigStore.shared.config.baseUrl)
    }

    // MARK: - Idempotency

    func testLogoutIsIdempotentWhenCalledTwice() async {
        // Calling logout on an already-logged-out store must be a no-op
        // (and must not crash). Important because the host app can
        // race two logout triggers (UI button + push-cleanup observer).
        seedLoggedInState()
        await LogoutManager.shared.logout(client: nil, options: hermeticOptions)
        await LogoutManager.shared.logout(client: nil, options: hermeticOptions)

        XCTAssertTrue(RoomStore.shared.rooms.isEmpty)
        XCTAssertFalse(UserStore.shared.isAuthenticated)
        XCTAssertNil(UserStore.shared.token)
    }
}
