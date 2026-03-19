//
//  UseChatWrapperInit.swift
//  XMPPChatCore
//
//  Chat wrapper initialization
//

import Foundation
import Combine

@MainActor
public class ChatWrapperInit: ObservableObject {
    @Published public var isInitialized: Bool = false
    @Published public var initializationError: Error?
    
    private var cancellables = Set<AnyCancellable>()
    
    public func initialize(
        config: ChatConfig,
        client: XMPPClient?,
        onComplete: @escaping () -> Void
    ) {
        Task {
            do {
                // Initialize XMPP client if needed
                if let client = client {
                    // Setup client
                }
                
                // Load initial data
                // Load rooms, messages, etc.
                
                await MainActor.run {
                    isInitialized = true
                    onComplete()
                }
            } catch {
                await MainActor.run {
                    initializationError = error
                }
            }
        }
    }
    
    public func reset() {
        isInitialized = false
        initializationError = nil
    }
}

/// High‑level wrapper around global chat state and XMPP client lifecycle.
///
/// This mirrors the behavior of the web `useChatWrapperInit` hook:
/// - initializes and stores the global `XMPPClient`
/// - applies `ChatConfig` via `ConfigStore`
/// - exposes wrapper state: `inited`, `showModal`, `isConnectionLost`
/// - optionally performs a lightweight rooms retry check when `enableRoomsRetry` is configured
@MainActor
public class ChatWrapperViewModel: ObservableObject {
    // MARK: - Nested Types
    
    /// Rooms retry state – equivalent to web `isRetrying` flag with `"norooms"` sentinel.
    public enum RoomsRetryState: Equatable {
        case none
        case retrying
        case noRooms
    }
    
    // MARK: - Published API (mirrors useChatWrapperInit result)
    
    /// Global XMPP client used by room list and chat room view models.
    @Published public private(set) var client: XMPPClient?
    
    /// Wrapper initialization flag – true when client is ready and basic checks are done.
    @Published public private(set) var inited: Bool = false
    
    /// Rooms retry state used to drive helper / loader UIs.
    @Published public private(set) var roomsRetryState: RoomsRetryState = .none
    
    /// Whether a blocking modal should be shown (e.g. when user credentials are missing).
    @Published public private(set) var showModal: Bool = false
    
    /// High‑level connection lost flag; driven by `ConnectionManager` status.
    @Published public private(set) var isConnectionLost: Bool = false
    
    /// Optional loading text to show while wrapper is initializing or retrying rooms.
    @Published public private(set) var loadingText: String?
    
    // MARK: - Internal State
    
    private let config: ChatConfig
    private let initialRoomJID: String?
    private let wasAutoSelected: Bool
    
    /// Cached current user id used by room / message view models.
    public private(set) var currentUserId: String = ""
    
    private let connectionManager: ConnectionManager
    private var cancellables = Set<AnyCancellable>()
    private var initializationTask: Task<Void, Never>?
    
    // MARK: - Init

    /// Create a new wrapper view model.
    ///
    /// - Parameters:
    ///   - config: Chat configuration (mirrors web `IConfig`).
    ///   - initialRoomJID: Optional room JID that should be opened/validated first.
    ///   - wasAutoSelected: Whether room was auto‑selected (e.g. via QR code).
    ///   - existingClient: Optional pre‑created `XMPPClient` to reuse instead of creating a new one.
    public init(
        config: ChatConfig,
        initialRoomJID: String? = nil,
        wasAutoSelected: Bool = false,
        existingClient: XMPPClient? = nil
    ) {
        self.config = config
        self.initialRoomJID = initialRoomJID
        self.wasAutoSelected = wasAutoSelected
        self.connectionManager = ConnectionManager.shared
        
        // Apply configuration globally (equivalent of Redux setConfig/setLangSource on web).
        ConfigStore.shared.mergeConfig(config)
        
        // Cache current user id for downstream view models.
        if let user = UserStore.shared.currentUser {
            self.currentUserId =
                user.id ??
                user.walletAddress ??
                user.username ??
                user.email ??
                ""
        }
        
        observeConnectionManager()
        
        // Kick off async initialization.
        self.initializationTask = Task { [weak self] in
            await self?.initialize(existingClient: existingClient)
        }
    }
    
    deinit {
        initializationTask?.cancel()
    }
    
    // MARK: - Public API
    
    /// Manually trigger re‑initialization (e.g. after login success).
    public func reinitialize() {
        initializationTask?.cancel()
        inited = false
        showModal = false
        roomsRetryState = .none
        loadingText = nil
        
        initializationTask = Task { [weak self] in
            await self?.initialize(existingClient: nil)
        }
    }
    
    // MARK: - Initialization Flow
    
    private func initialize(existingClient: XMPPClient?) async {
        // 0. Bring auth state in sync from config when possible.
        if UserStore.shared.currentUser == nil,
           config.jwtLogin?.enabled == true {
            _ = await UserStore.performJWTLoginIfConfigured()
        }

        if UserStore.shared.currentUser == nil,
           let userLogin = config.userLogin,
           userLogin.enabled,
           let configuredUser = userLogin.user {
            UserStore.shared.currentUser = configuredUser
            UserStore.shared.token = configuredUser.token
            UserStore.shared.refreshToken = configuredUser.refreshToken
            UserStore.shared.isAuthenticated = !((configuredUser.token ?? "").isEmpty)
        }

        // 1. Validate user credentials (mirrors web check for xmppUsername/xmppPassword).
        guard let user = UserStore.shared.currentUser,
              let xmppPassword = user.xmppPassword,
              !xmppPassword.isEmpty
        else {
            // No XMPP credentials – surface modal to hosting app.
            await MainActor.run {
                self.showModal = true
                self.inited = false
                self.loadingText = nil
            }
            return
        }
        
        let xmppUsername: String
        if let username = user.xmppUsername, !username.isEmpty {
            xmppUsername = username
        } else if let wallet = user.walletAddress, !wallet.isEmpty {
            xmppUsername = wallet
        } else {
            xmppUsername = user.email ?? ""
        }
        
        guard !xmppUsername.isEmpty else {
            await MainActor.run {
                self.showModal = true
                self.inited = false
                self.loadingText = nil
            }
            return
        }
        
        await MainActor.run {
            self.loadingText = "Connecting..."
            self.showModal = false
            self.inited = false
        }
        
        // 2. Reuse existing global client if available, otherwise create a new one.
        let activeClient: XMPPClient
        if let provided = existingClient {
            activeClient = provided
        } else if let global = ClientRegistry.shared.getGlobalXMPPClient() {
            activeClient = global
        } else {
            let settings = config.xmppSettings
            activeClient = XMPPClient(
                username: xmppUsername,
                password: xmppPassword,
                settings: settings
            )
            ClientRegistry.shared.setGlobalXMPPClient(activeClient)
        }
        
        await MainActor.run {
            self.client = activeClient
        }
        
        // 3. Wait for client to become fully connected (online + presences ready),
        //    with a sane timeout to avoid hanging the UI forever.
        let connected = await waitForClientToBeReady(client: activeClient, timeout: 15.0)
        
        if !connected {
            await MainActor.run {
                self.isConnectionLost = true
                self.inited = false
                self.loadingText = "Failed to connect. Retrying..."
            }
            return
        }
        
        // 4. Lightweight rooms retry flow – only if configured and an initial room was requested.
        if config.enableRoomsRetry?.enabled == true,
           let roomJID = initialRoomJID,
           !roomJID.isEmpty {
            await runRoomsRetryCheck(selectedRoomJID: roomJID)
        }
        
        // 5. Optionally trigger token refresh once at startup when configured.
        if let refreshTokens = config.refreshTokens, refreshTokens.enabled {
            await runTokenRefreshIfNeeded(refreshTokens: refreshTokens)
        }
        
        await MainActor.run {
            self.inited = true
            self.loadingText = nil
            // Connection might still flap later – `isConnectionLost` is driven by ConnectionManager.
        }
    }
    
    // MARK: - Helpers
    
    /// Wait until the XMPP client reports `isFullyConnected()` or the timeout elapses.
    private func waitForClientToBeReady(client: XMPPClient, timeout: TimeInterval) async -> Bool {
        let start = Date()
        
        // Fast path: already connected.
        if client.isFullyConnected() {
            return true
        }
        
        while Date().timeIntervalSince(start) < timeout {
            if client.isFullyConnected() {
                return true
            }
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
        }
        
        return client.isFullyConnected()
    }
    
    /// Lightweight approximation of web `enableRoomsRetry` + `getRoomsWithRetry`.
    ///
    /// It uses the existing `RoomsAPI.getRooms` to check whether the selected room exists.
    /// If the room cannot be found, we expose `.noRooms` which hosting UI can render
    /// with helper text from `config.enableRoomsRetry?.helperText`.
    private func runRoomsRetryCheck(selectedRoomJID: String) async {
        await MainActor.run {
            self.roomsRetryState = .retrying
            self.loadingText = "Loading rooms..."
        }
        
        do {
            let baseURL = URL(string: config.baseUrl ?? "https://api.ethoradev.com/v1")!
            let conferenceDomain = config.xmppSettings?.conference ?? "conference.xmpp.ethoradev.com"
            let rooms = try await RoomsAPI.getRooms(
                baseURL: baseURL,
                appId: config.appId ?? AppConfig.defaultAppId,
                conferenceDomain: conferenceDomain
            )
            
            let normalizedSelected = selectedRoomJID.components(separatedBy: "/").first ?? selectedRoomJID
            let hasSelectedRoom = rooms.contains { room in
                let normalizedRoom = room.jid.components(separatedBy: "/").first ?? room.jid
                return normalizedRoom == normalizedSelected
            }
            
            await MainActor.run {
                if hasSelectedRoom {
                    self.roomsRetryState = .none
                    self.loadingText = nil
                } else {
                    self.roomsRetryState = .noRooms
                    self.loadingText = nil
                }
            }
        } catch {
            await MainActor.run {
                self.roomsRetryState = .noRooms
                self.loadingText = nil
            }
        }
    }
    
    /// Execute configured token refresh logic once on startup when enabled.
    private func runTokenRefreshIfNeeded(refreshTokens: RefreshTokensConfig) async {
        // Prefer custom refresh function if provided.
        if let refreshFn = refreshTokens.refreshFunction {
            do {
                let result = try await refreshFn()
                await MainActor.run {
                    UserStore.shared.updateTokens(
                        token: result.accessToken,
                        refreshToken: result.refreshToken ?? UserStore.shared.refreshToken ?? ""
                    )
                }
                return
            } catch {
                // Silent failure – normal API flows (RoomsAPI, AuthAPI.refreshToken) already perform refresh.
                return
            }
        }
        
        // If no custom function is provided, fall back to AuthAPI.refreshToken using UserStore.refreshToken.
        let baseURL = URL(string: config.baseUrl ?? "https://api.ethoradev.com/v1")!
        let currentRefreshToken = UserStore.shared.refreshToken
        
        guard let refreshToken = currentRefreshToken, !refreshToken.isEmpty else {
            return
        }
        
        do {
            let (newToken, newRefreshToken) = try await AuthAPI.refreshToken(
                refreshToken: refreshToken,
                baseURL: baseURL
            )
            await MainActor.run {
                UserStore.shared.updateTokens(token: newToken, refreshToken: newRefreshToken)
            }
        } catch {
            // Ignore – regular API calls will surface refresh failures when needed.
        }
    }
    
    // MARK: - Connection Manager Integration
    
    private func observeConnectionManager() {
        connectionManager.$status
            .sink { [weak self] (status: ConnectionManager.ConnectionStatus) in
                guard let self = self else { return }
                self.isConnectionLost = (status == .disconnected)
            }
            .store(in: &cancellables)
    }
}
