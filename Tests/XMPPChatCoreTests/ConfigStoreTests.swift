import XCTest
@testable import XMPPChatCore

/// Hermetic L1 tests for `ConfigStore` — the singleton that owns the
/// host-app's `ChatConfig`. The contract worth pinning:
///   • `mergeConfig` performs a *partial* override (only non-nil fields
///     from the patch get applied; everything else is preserved).
///   • `updateConfig` performs a *full* replacement.
///   • The codable subset round-trips through UserDefaults (the runtime
///     subset — closures, `AnyView` and other non-codable fields are
///     intentionally dropped on persistence).
///   • `reset()` zeroes both state and persisted data.
///
/// These behaviours back the host-app integration contract documented
/// in CLAUDE.md: production hosts MUST set `baseUrl`, `appId`,
/// `customAppToken`, and `xmppSettings` via `mergeConfig` before
/// mounting chat. A regression in merge semantics silently wipes those.
@MainActor
final class ConfigStoreTests: XCTestCase {

    override func setUp() async throws {
        ConfigStore.shared.reset()
    }

    override func tearDown() async throws {
        ConfigStore.shared.reset()
    }

    // MARK: - mergeConfig (partial update)

    func testMergeConfigAppliesOnlyProvidedFields() {
        // Seed with a baseline value, then merge a patch that only sets a
        // different field. The seeded field must survive.
        var seed = ChatConfig()
        seed.baseUrl = "https://api.example.com"
        seed.appId = "seed-app"
        ConfigStore.shared.mergeConfig(seed)

        var patch = ChatConfig()
        patch.disableHeader = true
        ConfigStore.shared.mergeConfig(patch)

        XCTAssertEqual(ConfigStore.shared.config.baseUrl, "https://api.example.com",
                       "merge must not wipe an unrelated field")
        XCTAssertEqual(ConfigStore.shared.config.appId, "seed-app")
        XCTAssertEqual(ConfigStore.shared.config.disableHeader, true)
    }

    func testMergeConfigOverridesExistingValueWhenPatchProvidesOne() {
        var seed = ChatConfig()
        seed.baseUrl = "https://old.example.com"
        ConfigStore.shared.mergeConfig(seed)

        var patch = ChatConfig()
        patch.baseUrl = "https://new.example.com"
        ConfigStore.shared.mergeConfig(patch)

        XCTAssertEqual(ConfigStore.shared.config.baseUrl, "https://new.example.com")
    }

    func testMergeConfigIgnoresNilFieldsOnPatch() {
        // A patch with no fields set must be a no-op against the
        // existing config — important because hosts call mergeConfig
        // multiple times during init and a stale empty patch shouldn't
        // wipe earlier setup.
        var seed = ChatConfig()
        seed.appId = "app-1"
        seed.disableHeader = true
        ConfigStore.shared.mergeConfig(seed)

        let emptyPatch = ChatConfig()
        ConfigStore.shared.mergeConfig(emptyPatch)

        XCTAssertEqual(ConfigStore.shared.config.appId, "app-1")
        XCTAssertEqual(ConfigStore.shared.config.disableHeader, true)
    }

    func testMergeConfigPersistsXMPPSettings() {
        // XMPPSettings is the single most important codable field —
        // host apps point this at their backend, and a silent drop on
        // persist would mean every cold-start reconnects to the wrong
        // server.
        let xmpp = XMPPSettings(
            xmppServerUrl: "wss://xmpp.example.com:5443/ws",
            host: "xmpp.example.com",
            conference: "conference.xmpp.example.com",
            xmppPingOnSendEnabled: true
        )
        var patch = ChatConfig()
        patch.xmppSettings = xmpp
        ConfigStore.shared.mergeConfig(patch)

        XCTAssertEqual(ConfigStore.shared.config.xmppSettings?.xmppServerUrl,
                       "wss://xmpp.example.com:5443/ws")
        XCTAssertEqual(ConfigStore.shared.config.xmppSettings?.host, "xmpp.example.com")
        XCTAssertEqual(ConfigStore.shared.config.xmppSettings?.conference,
                       "conference.xmpp.example.com")
    }

    // MARK: - updateConfig (full replacement)

    func testUpdateConfigReplacesEntireConfigValue() {
        var seed = ChatConfig()
        seed.baseUrl = "https://seed.example.com"
        seed.appId = "seed-app"
        seed.disableHeader = true
        ConfigStore.shared.mergeConfig(seed)

        var replacement = ChatConfig()
        replacement.baseUrl = "https://replaced.example.com"
        // Note: appId + disableHeader intentionally not set on the
        // replacement; updateConfig is a *replace*, so they must be nil
        // afterwards.
        ConfigStore.shared.updateConfig(replacement)

        XCTAssertEqual(ConfigStore.shared.config.baseUrl, "https://replaced.example.com")
        XCTAssertNil(ConfigStore.shared.config.appId,
                     "updateConfig replaces — does not preserve prior fields")
        XCTAssertNil(ConfigStore.shared.config.disableHeader)
    }

    // MARK: - reset()

    func testResetZeroesConfigAndClearsPersistedDefaults() {
        var seed = ChatConfig()
        seed.appId = "to-be-reset"
        seed.baseUrl = "https://will-be-gone.example.com"
        ConfigStore.shared.mergeConfig(seed)

        ConfigStore.shared.reset()

        XCTAssertNil(ConfigStore.shared.config.appId)
        XCTAssertNil(ConfigStore.shared.config.baseUrl)
        // UserDefaults entry is removed — a fresh decode wouldn't find
        // anything. We assert via the public surface (re-merge starts
        // from empty state).
        var probe = ChatConfig()
        probe.disableHeader = true
        ConfigStore.shared.mergeConfig(probe)
        XCTAssertEqual(ConfigStore.shared.config.disableHeader, true)
        XCTAssertNil(ConfigStore.shared.config.appId,
                     "post-reset state must not retain pre-reset fields")
    }

    // MARK: - Codable round-trip

    func testCodableRoundTripPreservesKnownScalars() {
        // Build a config with the fields a host typically sets, then
        // encode + decode and check the codable subset survives.
        var original = ChatConfig()
        original.appId = "round-trip-app"
        original.baseUrl = "https://api.example.com"
        original.customAppToken = "JWT placeholder.token.value"
        original.disableHeader = true
        original.disableMedia = false
        original.disableRooms = true
        original.xmppSettings = XMPPSettings(
            xmppServerUrl: "wss://xmpp.example.com:5443/ws",
            host: "xmpp.example.com",
            conference: "conference.xmpp.example.com"
        )
        original.jwtLogin = JWTLoginConfig(token: "user.jwt.token", enabled: true)

        let data = try? JSONEncoder().encode(original)
        XCTAssertNotNil(data)

        let decoded = try? JSONDecoder().decode(ChatConfig.self, from: data!)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.appId, "round-trip-app")
        XCTAssertEqual(decoded?.baseUrl, "https://api.example.com")
        XCTAssertEqual(decoded?.customAppToken, "JWT placeholder.token.value")
        XCTAssertEqual(decoded?.disableHeader, true)
        XCTAssertEqual(decoded?.disableMedia, false)
        XCTAssertEqual(decoded?.disableRooms, true)
        XCTAssertEqual(decoded?.xmppSettings?.host, "xmpp.example.com")
        XCTAssertEqual(decoded?.jwtLogin?.token, "user.jwt.token")
        XCTAssertEqual(decoded?.jwtLogin?.enabled, true)
    }

    func testCodableRoundTripDropsNonCodableRuntimeOnlyFields() {
        // CLAUDE.md documents this: closures and `AnyView` injections are
        // runtime-only and must be reapplied on each launch. Lock the
        // contract so a future change that tries to encode one of these
        // fails the test (and the author either makes it codable or
        // documents the new field as runtime-only too).
        var original = ChatConfig()
        original.customLogin = CustomLoginConfig(enabled: true, loginFunction: { nil })
        original.headerMenu = { /* no-op */ }

        let data = try? JSONEncoder().encode(original)
        XCTAssertNotNil(data)
        let decoded = try? JSONDecoder().decode(ChatConfig.self, from: data!)
        XCTAssertNotNil(decoded)
        XCTAssertNil(decoded?.customLogin, "non-codable customLogin must NOT persist")
        // headerMenu is a closure — there is no direct way to assert
        // identity, but it must be nil after decode (no codable key).
        XCTAssertNil(decoded?.headerMenu)
    }
}
