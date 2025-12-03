//
//  XMPPClient.swift
//  XMPPChatCore
//
//  Translated from TypeScript xmppClient.ts
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
    private var service: String
    internal var conference: String
    public private(set) var username: String
    private var password: String
    private var resource: String = "default"
    
    public private(set) var status: ConnectionStatus = .offline
    public private(set) var presencesReady: Bool = false
    
    // Reconnection
    private var reconnectAttempts: Int = 0
    private let maxReconnectAttempts: Int = 5
    private let reconnectDelay: TimeInterval = 2.0
    private var reconnecting: Bool = false
    private var reconnectTimer: Timer?
    private var offlineReconnectAttempts: Int = 0
    private let maxOfflineReconnectAttempts: Int = 10
    private let reconnectBaseDelayMs: TimeInterval = 1.0
    private var pausedDueToOfflineCap: Bool = false
    
    // Connection state tracking
    private var isConnecting: Bool = false
    private var connectionReplaced: Bool = false // Track if connection was replaced by new one
    
    // Ping/Pong
    private var pingInterval: Timer?
    private var pingTimeout: Timer?
    private var lastPingId: String?
    private let pingIntervalMs: TimeInterval = 60.0
    private let pongTimeoutMs: TimeInterval = 1.0
    private var pingInFlight: Bool = false
    private let idleThresholdMs: TimeInterval = 60.0
    private var lastActivityTs: TimeInterval = Date().timeIntervalSince1970
    private var idlePingTimeout: Timer?
    
    // Message Queue
    private var messageQueue: [() async -> Bool] = []
    private var inFlightIds: Set<String> = []
    private var processingQueue: Bool = false
    
    // Connection Steps
    private var connectionSteps: [ConnectionStep] = []
    
    // XMPP Stream
    internal var xmppStream: XMPPStream?
    
    // Stanza handlers
    internal var stanzaHandlers: StanzaHandlers?
    private var handleStanzas: HandleStanzas?
    
    // Track rooms that have received presence responses (to avoid duplicate sends)
    private var roomsWithPresenceResponse: Set<String> = []
    
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
    // Match TypeScript: async initializeClient()
    private func initializeClient() {
        // Prevent multiple simultaneous connection attempts
        guard !isConnecting else {
            NSLog("⚠️ Connection already in progress, skipping initializeClient")
            print("⚠️ Connection already in progress, skipping initializeClient")
            return
        }
        
        // If connection was replaced, don't reconnect (another connection is active)
        if connectionReplaced {
            NSLog("⚠️ Connection was replaced by new connection, not reconnecting")
            print("⚠️ Connection was replaced by new connection, not reconnecting")
            connectionReplaced = false // Reset flag
            return
        }
        
        isConnecting = true
        
        do {
            logStep("initializeClient:start")
            
            // Match TypeScript: if (this.client) { await this.disconnect(); }
            if xmppStream != nil {
                logStep("initializeClient:disconnect-previous")
                Task {
                    await disconnect()
                }
            }
            
            // Match TypeScript: const url = this.devServer || `wss://xmpp.ethoradev.com:5443/ws`;
            let url = devServer.isEmpty ? "wss://xmpp.ethoradev.com:5443/ws" : devServer
            
            // Match TypeScript: this.host = url.match(/wss:\/\/([^:/]+)/)?.[1] || '';
            if let urlObj = URL(string: url),
               let hostComponent = urlObj.host {
                self.host = hostComponent
                self.conference = "conference.\(hostComponent)"
            }
            
            // Match TypeScript: console.log('+-+-+-+-+-+-+-+-+ ', { username: this.username });
            NSLog("+-+-+-+-+-+-+-+-+ ")
            print("+-+-+-+-+-+-+-+-+ ")
            print("username: \(username)")
            
            self.devServer = url
            
            // Match TypeScript: this.client = xmpp.client({ service: url, username: this.username, password: this.password });
            // Initialize XMPP stream
            xmppStream = XMPPStream(service: devServer)
            xmppStream?.delegate = self
            
            // Match TypeScript: if (this.client.setMaxListeners) { this.client.setMaxListeners(50); }
            // (Not applicable in Swift, but noted for completeness)
            
            // Match TypeScript: this.attachEventListeners();
            attachEventListeners()
            
            // Match TypeScript: this.client.start().catch((error) => { console.error('Error starting client:', error); });
            Task {
                do {
                    xmppStream?.connect(username: username, password: password, resource: resource)
                } catch {
                    NSLog("Error starting client: %@", error.localizedDescription)
                    print("Error starting client: \(error.localizedDescription)")
                    isConnecting = false
                }
            }
            
            // Match TypeScript: this.startAdaptivePing();
            startAdaptivePing()
            
            logStep("initializeClient:started")
        } catch {
            NSLog("Error initializing client: %@", error.localizedDescription)
            print("Error initializing client: \(error.localizedDescription)")
            isConnecting = false
        }
    }
    
    // Match TypeScript: async disconnect()
    public func disconnect() async {
        // Match TypeScript: if (!this.client) return;
        guard let stream = xmppStream else { return }
        
        do {
            // Match TypeScript: if (this.pingInterval) clearInterval(this.pingInterval);
            pingInterval?.invalidate()
            
            // Match TypeScript: if (this.pingTimeout) clearTimeout(this.pingTimeout);
            pingTimeout?.invalidate()
            
            // Match TypeScript: if (this.idlePingTimeout) clearTimeout(this.idlePingTimeout as any);
            idlePingTimeout?.invalidate()
            
            // Match TypeScript: if (this.reconnectTimer) { clearTimeout(this.reconnectTimer); this.reconnectTimer = null; }
            if let timer = reconnectTimer {
                timer.invalidate()
                reconnectTimer = nil
            }
            
            // Match TypeScript: this.client?.transport?.socket?.close?.();
            stream.disconnect()
            
            // Match TypeScript: await this.client.stop();
            xmppStream = nil
            status = .offline
            presencesReady = false
            // Clear presence response tracking when disconnecting
            clearPresenceResponseTracking()
            
            // Match TypeScript: console.log('Client disconnected');
            NSLog("Client disconnected")
            print("Client disconnected")
        } catch {
            // Match TypeScript: console.error('Error disconnecting client:', error);
            NSLog("Error disconnecting client: %@", error.localizedDescription)
            print("Error disconnecting client: \(error.localizedDescription)")
        }
    }
    
    // Match TypeScript: attachEventListeners()
    private func attachEventListeners() {
        guard xmppStream != nil else { return }
        
        // Event listeners are handled via XMPPStreamDelegate
        // The actual event handling happens in the XMPPStreamDelegate methods
    }
    
    // MARK: - Reconnection
    private func scheduleReconnect(reason: String) {
        guard status != .online else { return }
        guard reconnectTimer == nil else { return }
        guard isBrowserOnline() else {
            logStep("scheduleReconnect:skip-offline:\(reason)")
            return
        }
        guard !pausedDueToOfflineCap else {
            logStep("scheduleReconnect:paused-cap:\(reason)")
            return
        }
        
        guard offlineReconnectAttempts < maxOfflineReconnectAttempts else {
            pausedDueToOfflineCap = true
            logStep("scheduleReconnect:cap-reached:\(reason)")
            return
        }
        
        let attempt = offlineReconnectAttempts + 1
        let delay = min(reconnectBaseDelayMs * Double(attempt), 10.0)
        logStep("scheduleReconnect:\(reason):in:\(delay)")
        
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.reconnectTimer = nil
            guard self.isBrowserOnline() && !self.pausedDueToOfflineCap else { return }
            self.offlineReconnectAttempts += 1
            Task {
                await self.reconnect()
            }
        }
    }
    
    private func reconnect() async {
        presencesReady = false
        
        guard !reconnecting else { return }
        guard isBrowserOnline() else {
            logStep("reconnect:skipped-offline")
            return
        }
        guard !pausedDueToOfflineCap else {
            logStep("reconnect:paused-due-to-cap")
            return
        }
        
        reconnecting = true
        defer { reconnecting = false }
        
        logStep("reconnect:start")
        await disconnect()
        initializeClient()
        logStep("reconnect:end")
    }
    
    // MARK: - Connection Status
    public func ensureConnected(timeout: TimeInterval = 10.0) async throws {
        guard status != .online else { return }
        
        if status == .offline || status == .error {
            logStep("ensureConnected:trigger-reconnect:\(status.rawValue)")
            scheduleReconnect(reason: "ensure-connected")
            throw XMPPError.notConnected
        }
        
        if status == .connecting {
            // Wait for connection with timeout
            let startTime = Date()
            while status == .connecting {
                if Date().timeIntervalSince(startTime) > timeout {
                    throw XMPPError.connectionTimeout
                }
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
            
            if status != .online {
                throw XMPPError.connectionError
            }
        }
    }
    
    // MARK: - Message Queue
    private func enqueue(_ task: @escaping () async -> Bool) async -> Bool {
        return await withCheckedContinuation { continuation in
            messageQueue.append {
                let result = await task()
                continuation.resume(returning: result)
                return result
            }
            Task {
                await processQueue()
            }
        }
    }
    
    private func processQueue() async {
        guard !processingQueue else { return }
        processingQueue = true
        defer { processingQueue = false }
        
        while !messageQueue.isEmpty {
            do {
                try await ensureConnected()
            } catch {
                break
            }
            
            guard let next = messageQueue.first else { break }
            let ok = await next()
            
            if ok {
                messageQueue.removeFirst()
            } else {
                break
            }
        }
        
        if !messageQueue.isEmpty && status == .online {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            await processQueue()
        }
    }
    
    private func withIdLock<T>(_ id: String?, _ fn: () async throws -> T) async throws -> T {
        guard let id = id else { return try await fn() }
        guard !inFlightIds.contains(id) else {
            throw XMPPError.duplicateRequest
        }
        inFlightIds.insert(id)
        defer {
            inFlightIds.remove(id)
        }
        return try await fn()
    }
    
    // MARK: - Activity Tracking
    // Match TypeScript: private markActivity()
    private func markActivity() {
        // Match TypeScript: this.lastActivityTs = Date.now();
        lastActivityTs = Date().timeIntervalSince1970
        // Match TypeScript: this.scheduleAdaptivePing();
        scheduleAdaptivePing()
    }
    
    // Match TypeScript: private scheduleAdaptivePing()
    private func scheduleAdaptivePing() {
        if idlePingTimeout != nil {
            idlePingTimeout?.invalidate()
        }
        
        // Match TypeScript: const idleTime = 2000;
        let idleTime: TimeInterval = 2.0
        // Match TypeScript: const pongWait = 2000;
        let pongWait: TimeInterval = 2.0
        
        idlePingTimeout = Timer.scheduledTimer(withTimeInterval: idleTime, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            guard self.status == .online && !self.pingInFlight else { return }
            
            // Match TypeScript: this.pingInFlight = true; const pingId = sendPing(this.client, this.host);
            self.pingInFlight = true
            // TODO: Implement sendPing - for now, we'll skip ping
            // In production, implement proper XMPP ping
            // let pingId = sendPing(self.xmppStream, self.host)
            // self.lastPingId = pingId
            
            // Match TypeScript pong listener and timeout logic
            // This would be implemented when we have proper XMPP ping/pong
        }
    }
    
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
    private func wrapWithConnectionCheck<T>(_ operation: () async throws -> T) async throws -> T {
        try await ensureConnected()
        return try await operation()
    }
    
    // MARK: - Presence Operations
    // Match TypeScript: async sendAllPresencesAndMarkReady()
    private func sendAllPresencesAndMarkReady() async {
        // Match TypeScript: this.presencesReady = false;
        presencesReady = false
        
        // Match TypeScript: await this.allRoomPresencesStanza();
        await allRoomPresencesStanza()
        
        // Match TypeScript: this.presencesReady = true;
        presencesReady = true
    }
    
    // Match TypeScript: async allRoomPresencesStanza()
    private func allRoomPresencesStanza() async {
        // Match TypeScript: await allRoomPresences(this.client);
        // Note: In TypeScript, this gets rooms from store.getState().rooms.rooms
        // In Swift, we'll send presence to rooms after they're loaded via API
        // This is called from sendAllPresencesAndMarkReady, but actual room presence
        // will be sent later when rooms are loaded
    }
    
    // Public method to send presence to all rooms (called after rooms are loaded)
    // Match TypeScript: allRoomPresences gets rooms from store.getState().rooms.rooms
    // In Swift, we pass roomJIDs after loading from API
    public func sendPresenceToAllRooms(roomJIDs: [String]) async {
        // Match TypeScript: await allRoomPresences(this.client);
        // This calls allRoomPresences which internally calls presenceInRoom for each room
        await operations.allRoomPresences(roomJIDs: roomJIDs)
    }
    
    // MARK: - Adaptive Ping
    // Match TypeScript: private startAdaptivePing()
    private func startAdaptivePing() {
        // Match TypeScript adaptive ping logic
        // This is already partially implemented, but we should match the exact logic
        scheduleAdaptivePing()
    }
    
}

// MARK: - XMPPStreamDelegate
extension XMPPClient: XMPPStreamDelegate {
    public func xmppStreamDidConnect(_ stream: XMPPStream) {
        // Match TypeScript: this.client.on('connecting', () => { ... })
        // Match TypeScript: console.log('Client is connecting...');
        NSLog("Client is connecting...")
        print("Client is connecting...")
        status = .connecting
        logStep("event:connecting")
    }
    
    // Match TypeScript: this.client.on('online', async (jid) => { ... })
    // This should be called when XMPP stream becomes online
    // We need to add a method to XMPPStreamDelegate for this
    public func xmppStreamDidBecomeOnline(_ stream: XMPPStream, jid: String) {
        Task {
            await handleOnlineEvent(jid: jid)
        }
    }
    
    private func handleOnlineEvent(jid: String) async {
        // Match TypeScript: this.client.on('online', async (jid) => { ... })
        do {
            // Match TypeScript: this.resource = jid.resource || 'default';
            // Extract resource from JID: user@host/resource
            if let resourcePart = jid.components(separatedBy: "/").last, !resourcePart.isEmpty {
                resource = resourcePart
            } else {
                resource = "default"
            }
            
            // Match TypeScript: console.log('Client is online.', new Date());
            NSLog("Client is online. %@", Date().description)
            print("Client is online. \(Date())")
            
            // Match TypeScript: this.status = 'online';
            status = .online
            isConnecting = false // Connection successful, reset flag
            
            // Match TypeScript: this.reconnectAttempts = 0;
            reconnectAttempts = 0
            
            // Match TypeScript: this.offlineReconnectAttempts = 0;
            offlineReconnectAttempts = 0
            
            // Match TypeScript: this.pausedDueToOfflineCap = false;
            pausedDueToOfflineCap = false
            
            // Match TypeScript: if (this.reconnectTimer) { clearTimeout(this.reconnectTimer); this.reconnectTimer = null; }
            if let timer = reconnectTimer {
                timer.invalidate()
                reconnectTimer = nil
            }
            
            // Notify delegate that client is connected
            delegate?.xmppClientDidConnect(self)
            
            // Post notification for message loader queue
            NotificationCenter.default.post(
                name: NSNotification.Name("XMPPClientDidConnect"),
                object: self
            )
            
            // Match TypeScript: this.client.send(xml('presence'));
            // IMPORTANT: Send simple presence to XMPP server first (announcing online status)
            // This must be done BEFORE sending presence to rooms
            let presenceStanza = XMPPStanza(name: "presence")
            xmppStream?.send(presenceStanza)
            NSLog("📤 Sent initial presence to XMPP server (announcing online)")
            print("📤 Sent initial presence to XMPP server (announcing online)")
            
            // Wait a bit for the server to process the initial presence
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            // Match TypeScript: await this.sendAllPresencesAndMarkReady();
            await sendAllPresencesAndMarkReady()
            
            // Match TypeScript: this.logStep('event:online');
            logStep("event:online")
            
            // Match TypeScript: this.processQueue().catch(() => {});
            Task {
                await processQueue()
            }
            
            // Match TypeScript: await this.drainHeap();
            // Note: drainHeap is for resending failed messages from heap
            // We can implement this later if needed
            // await drainHeap()
            
        } catch {
            // Match TypeScript: console.log('Error', error);
            NSLog("Error %@", error.localizedDescription)
            print("Error \(error)")
        }
    }
    
    public func xmppStreamDidDisconnect(_ stream: XMPPStream, error: Error?) {
        // Match TypeScript: this.client.on('disconnect', () => { ... })
        // Match TypeScript: console.log('Disconnected from server.');
        NSLog("Disconnected from server.")
        print("Disconnected from server.")
        
        // Log disconnect details if available
        if let error = error {
            if let nsError = error as NSError? {
                NSLog("   Disconnect Error Domain: %@", nsError.domain)
                NSLog("   Disconnect Error Code: %ld", nsError.code)
                NSLog("   Disconnect Error Description: %@", nsError.localizedDescription)
                if let reason = nsError.userInfo["reason"] as? String {
                    NSLog("   Disconnect Reason: %@", reason)
                }
                if let code = nsError.userInfo["disconnectCode"] as? UInt16 {
                    NSLog("   WebSocket Close Code: %u", code)
                }
                print("   Disconnect Error Domain: \(nsError.domain)")
                print("   Disconnect Error Code: \(nsError.code)")
                print("   Disconnect Error Description: \(nsError.localizedDescription)")
                if let reason = nsError.userInfo["reason"] as? String {
                    print("   Disconnect Reason: \(reason)")
                }
                if let code = nsError.userInfo["disconnectCode"] as? UInt16 {
                    print("   WebSocket Close Code: \(code)")
                }
            }
        }
        
        // Check if disconnect was due to "Replaced by new connection"
        var wasReplaced = false
        if let error = error {
            if let nsError = error as NSError? {
                let description = nsError.localizedDescription.lowercased()
                if description.contains("replaced by new connection") || description.contains("conflict") {
                    wasReplaced = true
                    connectionReplaced = true
                }
                if let reason = nsError.userInfo["reason"] as? String {
                    if reason.lowercased().contains("replaced") || reason.lowercased().contains("conflict") {
                        wasReplaced = true
                        connectionReplaced = true
                    }
                }
                if nsError.userInfo["replaced"] as? Bool == true {
                    wasReplaced = true
                    connectionReplaced = true
                }
            }
        }
        
        status = .offline
        presencesReady = false
        logStep("event:disconnect")
        // Match TypeScript: if (this.pingInterval) clearInterval(this.pingInterval);
        pingInterval?.invalidate()
        isConnecting = false // Reset connection flag on disconnect
        
        // Only schedule reconnect if connection wasn't replaced
        if wasReplaced || connectionReplaced {
            NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            NSLog("⚠️⚠️⚠️ NOT RECONNECTING - Connection was replaced ⚠️⚠️⚠️")
            NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("⚠️⚠️⚠️ NOT RECONNECTING - Connection was replaced ⚠️⚠️⚠️")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            connectionReplaced = false // Reset flag
        } else {
            scheduleReconnect(reason: "event:disconnect")
        }
    }
    
    public func xmppStream(_ stream: XMPPStream, didReceiveStanza stanza: XMPPStanza) {
        // Log raw XMPP stanza - especially important for debugging get-history
        // let rawXML = stanza.toXML()
        // NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        // NSLog("📥📥📥 RAW XMPP STANZA RECEIVED 📥📥📥")
        // NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        // NSLog("   Stanza Name: %@", stanza.name)
        // NSLog("   Stanza Type: %@", stanza.attributes["type"] ?? "none")
        // NSLog("   Stanza From: %@", stanza.attributes["from"] ?? "none")
        // NSLog("   Stanza To: %@", stanza.attributes["to"] ?? "none")
        // NSLog("   Stanza ID: %@", stanza.attributes["id"] ?? "none")
        // NSLog("   XML Length: %lu bytes", rawXML.count)
        // NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        // NSLog("📋 FULL RAW XML:")
        // NSLog("%@", rawXML)
        // NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        // print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        // print("📥📥📥 RAW XMPP STANZA RECEIVED 📥📥📥")
        // print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        // print("   Stanza Name: \(stanza.name)")
        // print("   Stanza Type: \(stanza.attributes["type"] ?? "none")")
        // print("   Stanza From: \(stanza.attributes["from"] ?? "none")")
        // print("   Stanza To: \(stanza.attributes["to"] ?? "none")")
        // print("   Stanza ID: \(stanza.attributes["id"] ?? "none")")
        // print("   XML Length: \(rawXML.count) bytes")
        // print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        // print("📋 FULL RAW XML:")
        // print(rawXML)
        // print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        // Match TypeScript: this.client.on('stanza', (stanza) => { ... })
        // Match TypeScript: this.lastActivityTs = Date.now();
        lastActivityTs = Date().timeIntervalSince1970
        
        // Match TypeScript: try { if (this.lastPingId && isPong(stanza, this.lastPingId)) { this.handlePong(); } } catch {}
        do {
            if let pingId = lastPingId, isPong(stanza, pingId: pingId) {
                handlePong()
            }
        } catch {
            // Ignore errors - match TypeScript empty catch
        }
        
        // Match TypeScript: handleStanza.bind(this, stanza, this)();
        handleStanza(stanza)
        
        // Also notify delegate
        delegate?.xmppClient(self, didReceiveStanza: stanza)
    }
    
    public func xmppStream(_ stream: XMPPStream, didSendStanza stanza: XMPPStanza) {
        // Stanza sent
    }
    
    // Handle error event - Match TypeScript: this.client.on('error', (error) => { ... })
    public func xmppStream(_ stream: XMPPStream, didReceiveError error: Error) {
        // Match TypeScript: console.error('XMPP client error:', error);
        NSLog("XMPP client error: %@", error.localizedDescription)
        print("XMPP client error: \(error.localizedDescription)")
        status = .error
        logStep("event:error")
        scheduleReconnect(reason: "event:error")
    }
    
    private func isPong(_ stanza: XMPPStanza, pingId: String) -> Bool {
        // Check if stanza is a pong response to our ping
        return stanza.name == "iq" && 
               stanza.attributes["id"] == pingId &&
               stanza.attributes["type"] == "result"
    }
    
    private func handlePong() {
        pingTimeout?.invalidate()
        pingTimeout = nil
        lastPingId = nil
        pingInFlight = false
    }
    
    private func handleStanza(_ stanza: XMPPStanza) {
        // Initialize handlers if needed
        if stanzaHandlers == nil {
            stanzaHandlers = StanzaHandlers(client: self)
            setupStanzaHandlers()
        }
        
        // Initialize HandleStanzas router if needed
        if handleStanzas == nil {
            handleStanzas = HandleStanzas(client: self, stanzaHandlers: stanzaHandlers!)
        }
        
        // Route stanza through HandleStanzas (matches TypeScript handleStanza function)
        // This will call all appropriate handlers in the correct order
        handleStanzas?.handleStanza(stanza)
    }
    
    /// Process incoming message (save to cache, post notification for RoomListViewModel)
    /// This ensures messages are available even if no ChatRoomViewModel is active
    private func processIncomingMessage(_ message: Message) {
        let roomJID = message.roomJid.components(separatedBy: "/").first ?? message.roomJid
        
        // MessageCache is @MainActor, so we need to call it from main actor context
        Task { @MainActor in
            // Load existing messages from cache
            var cachedMessages = MessageCache.shared.loadMessages(forRoomJID: roomJID) ?? []
            
            // Check if message already exists (avoid duplicates)
            if !cachedMessages.contains(where: { $0.id == message.id || ($0.xmppId != nil && $0.xmppId == message.id) || (message.xmppId != nil && $0.id == message.xmppId) }) {
                // Add message to cache
                cachedMessages.append(message)
                
                // Sort by timestamp
                cachedMessages.sort { msg1, msg2 in
                    let ts1 = msg1.timestamp ?? 0
                    let ts2 = msg2.timestamp ?? 0
                    return ts1 < ts2
                }
                
                // Save to cache (limit to 100 messages per room)
                let messagesToSave = Array(cachedMessages.suffix(100))
                MessageCache.shared.saveMessages(messagesToSave, forRoomJID: roomJID)
                
                // Post notification for RoomListViewModel to update room.messages
                NotificationCenter.default.post(
                    name: NSNotification.Name("RoomMessagesUpdated"),
                    object: self,
                    userInfo: [
                        "roomJID": roomJID,
                        "messageCount": messagesToSave.count,
                        "message": message
                    ]
                )
                
                print("✅ XMPPClient: Processed history message - saved to cache, posted notification")
            } else {
                print("⚠️ XMPPClient: Message already exists in cache, skipping")
            }
        }
    }
    
    private func setupStanzaHandlers() {
        guard let handlers = stanzaHandlers else { return }
        
        // Set up real-time message handler
        handlers.onMessageReceived = { [weak self] message, roomJID in
            NSLog("📨 XMPPClient: Real-time message in room %@", roomJID)
            print("📨 XMPPClient: Real-time message in room \(roomJID)")
            guard let self = self else { return }
            self.delegate?.xmppClient(self, didReceiveMessage: message)
        }
        
        // Set up history message handler
        handlers.onHistoryMessageReceived = { [weak self] message, roomJID in
            NSLog("📜 XMPPClient: History message in room %@", roomJID)
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("📜 XMPPClient: History message received")
            print("   Room JID: \(roomJID)")
            print("   Message ID: \(message.id)")
            print("   Message body: \(message.body.prefix(50))...")
            print("   Message timestamp: \(message.timestamp?.description ?? "nil")")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            
            guard let self = self else {
                print("⚠️ XMPPClient: self is nil, cannot process history message")
                return
            }
            
            // Process incoming message (save to cache, update room, etc.)
            // This ensures messages are available even if no ChatRoomViewModel is active
            self.processIncomingMessage(message)
            
            // Notify delegate (for ChatRoomViewModel if active)
            print("📤 XMPPClient: Notifying delegate about history message")
            self.delegate?.xmppClient(self, didReceiveMessage: message)
            print("✅ XMPPClient: Delegate notified")
        }
        
        // Set up composing (typing) indicator handler
        handlers.onComposingChanged = { [weak self] roomJID, composingList, isComposing in
            print("⌨️ XMPPClient: Composing changed in room \(roomJID) - isComposing: \(isComposing), users: \(composingList)")
            guard let self = self else { return }
            // Post notification for composing change so ChatRoomViewModel can observe it
            NotificationCenter.default.post(
                name: NSNotification.Name("XMPPComposingChanged"),
                object: self,
                userInfo: [
                    "roomJID": roomJID,
                    "composingList": composingList,
                    "isComposing": isComposing
                ]
            )
        }
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

