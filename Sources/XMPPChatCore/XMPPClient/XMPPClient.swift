//
//  XMPPClient.swift
//  XMPPChatCore
//
//

import Foundation
import Combine

public protocol XMPPClientDelegate: AnyObject {
    func xmppClientDidConnect(_ client: XMPPClient)
    func xmppClientDidDisconnect(_ client: XMPPClient)
    func xmppClient(_ client: XMPPClient, didReceiveMessage message: Message)
    func xmppClient(_ client: XMPPClient, didReceiveStanza stanza: XMPPStanza)
    func xmppClient(_ client: XMPPClient, didChangeStatus status: ConnectionStatus)
}

public class XMPPClient {
    // MARK: - Properties
    public weak var delegate: XMPPClientDelegate?
    
    internal var devServer: String
    internal var host: String
    internal var service: String
    internal var conference: String
    public private(set) var username: String
    internal var password: String
    internal var resource: String = "default"
    
    public private(set) var status: ConnectionStatus = .offline
    public private(set) var presencesReady: Bool = false
    
    // Reconnection
    internal var reconnectAttempts: Int = 0
    private let maxReconnectAttempts: Int = 5
    private let reconnectDelay: TimeInterval = 2.0
    internal var reconnecting: Bool = false
    internal var reconnectTimer: Timer?
    internal var offlineReconnectAttempts: Int = 0
    private let maxOfflineReconnectAttempts: Int = 10
    internal let reconnectBaseDelayMs: TimeInterval = 1.0
    internal var pausedDueToOfflineCap: Bool = false
    
    // Connection state tracking
    internal var isConnecting: Bool = false
    internal var connectionReplaced: Bool = false // Track if connection was replaced by new one
    
    // Ping/Pong
    internal var pingInterval: Timer?
    internal var pingTimeout: Timer?
    internal var lastPingId: String?
    private let pingIntervalMs: TimeInterval = 60.0
    private let pongTimeoutMs: TimeInterval = 1.0
    internal var pingInFlight: Bool = false
    private let idleThresholdMs: TimeInterval = 60.0
    internal var lastActivityTs: TimeInterval = Date().timeIntervalSince1970
    internal var idlePingTimeout: Timer?
    
    // Message Queue
    internal var messageQueue: [() async -> Bool] = []
    internal var inFlightIds: Set<String> = []
    internal var processingQueue: Bool = false
    
    // Connection Steps
    internal var connectionSteps: [ConnectionStep] = []
    
    // XMPP Stream
    internal var xmppStream: XMPPStream?
    
    // Stanza handlers
    internal var stanzaHandlers: StanzaHandlers?
    internal var handleStanzas: HandleStanzas?
    
    // Track rooms that have received presence responses (to avoid duplicate sends)
    internal var roomsWithPresenceResponse: Set<String> = []
    
    // MARK: - Initialization
    public init(
        username: String,
        password: String,
        settings: XMPPSettings? = nil
    ) {
        self.username = username
        self.password = password
        
        self.devServer = settings?.devServer ?? "wss://xmpp.ethoradev.com:5443/ws"
        self.host = settings?.host ?? "xmpp.ethoradev.com"
        self.service = settings?.conference ?? "conference.xmpp.ethoradev.com"
        self.conference = "conference.\(self.host)"
        
        initializeClient()
    }
    
    // MARK: - Public Methods
    public func checkOnline() -> Bool {
        return status == .online
    }
    
    /// Check if client is fully connected and ready to send messages
    /// This includes being online AND having sent presence to all rooms
    public func isFullyConnected() -> Bool {
        return status == .online && presencesReady
    }
    
    /// Check if client is currently in the process of connecting
    public func checkConnecting() -> Bool {
        return status == .connecting
    }
    
    public func getConnectionSteps() -> [ConnectionStep] {
        return connectionSteps
    }
    
    // MARK: - Presence Response Tracking
    /// Check if a room has already received a presence response
    internal func hasPresenceResponseForRoom(_ roomJID: String) -> Bool {
        let bareRoomJID = roomJID.components(separatedBy: "/").first ?? roomJID
        return roomsWithPresenceResponse.contains(bareRoomJID)
    }
    
    /// Mark a room as having received a presence response
    internal func markPresenceResponseReceived(for roomJID: String) {
        let bareRoomJID = roomJID.components(separatedBy: "/").first ?? roomJID
        roomsWithPresenceResponse.insert(bareRoomJID)
    }
    
    /// Clear presence response tracking (useful when disconnecting)
    internal func clearPresenceResponseTracking() {
        roomsWithPresenceResponse.removeAll()
    }
    
    // MARK: - Connection Management
    // Extracted to XMPPClient+Connection.swift
    
    // MARK: - Reconnection
    // Extracted to XMPPClient+Connection.swift
    
    // MARK: - Connection Status and Utilities
    // Extracted to XMPPClient+Operations.swift
    
    // MARK: - Activity Tracking
    // Extracted to XMPPClient+Pings.swift
    
    // MARK: - Helper Methods
    private func isBrowserOnline() -> Bool {
        // On iOS, check network reachability
        // This is a simplified version
        return true
    }
    
    private func logStep(_ step: String) {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        connectionSteps.append(ConnectionStep(timestamp: timestamp, step: step))
        if connectionSteps.count > 200 {
            connectionSteps.removeFirst()
        }
    }
    
    // MARK: - Wrapper Methods
    // Extracted to XMPPClient+Operations.swift
    
    // MARK: - Presence Operations
    // Extracted to XMPPClient+Operations.swift
    
    // MARK: - Adaptive Ping
    // Extracted to XMPPClient+Pings.swift
    
}

// MARK: - XMPPStreamDelegate
// Extracted to XMPPClient+Stream.swift
    
    // MARK: - Stanza Handling
    // Extracted to XMPPClient+Handlers.swift
    }
}

// MARK: - Errors
public enum XMPPError: Error {
    case notConnected
    case connectionTimeout
    case connectionError
    case duplicateRequest
    case invalidStanza
    case sendFailed
}

