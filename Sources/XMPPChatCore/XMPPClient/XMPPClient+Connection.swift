//
//  XMPPClient+Connection.swift
//  XMPPChatCore
//

import Foundation

extension XMPPClient {
    // MARK: - Connection Management
    internal func initializeClient() {
        // Prevent multiple simultaneous connection attempts
        guard !isConnecting else {
            //NSlog("⚠️ Connection already in progress, skipping initializeClient")
            //print("⚠️ Connection already in progress, skipping initializeClient")
            return
        }
        
        if status == .online {
            //NSlog("⚠️ Already connected, skipping initializeClient")
            //print("⚠️ Already connected, skipping initializeClient")
            return
        }
        
        isConnecting = true
        
        do {
            logStep("initializeClient:start")
            
            if let existingStream = xmppStream {
                NotificationCenter.default.post(
                    name: NSNotification.Name("XMPPConnectionStatusChanged"),
                    object: nil,
                    userInfo: ["status": "offline", "reason": "Initializing new connection..."]
                )
                // We're already in do-catch, and disconnect is async
                Task {
                    await disconnect()
                    isConnecting = true // Reset after disconnect
                }
            }
            
            // Get credentials from Store if needed
            // let url = ConfigStore.shared.config.devServer
            //NSlog("+-+-+-+-+-+-+-+-+ ")
            //print("+-+-+-+-+-+-+-+-+ ")
            //print("username: \(username)")
            
            let url = self.devServer
            
            // Initialize XMPP stream
            xmppStream = XMPPStream(service: url)
            xmppStream?.delegate = self
            xmppStream?.connect(username: username, password: password, resource: resource)
            
            attachEventListeners()
            
            // Timeout safety for connection attempt
            Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                if isConnecting && status != .online {
                    //NSlog("⚠️ Connection attempt timed out")
                    //print("⚠️ Connection attempt timed out")
                    isConnecting = false
                }
            }
            
            startAdaptivePing()
            
            logStep("initializeClient:started")
            
        } catch {
            //NSlog("Error initializing client: %@", error.localizedDescription)
            //print("Error initializing client: \(error.localizedDescription)")
            isConnecting = false
        }
    }
    
    public func disconnect() async {
        guard let stream = xmppStream else { return }
        
        do {
            pingInterval?.invalidate()
            
            pingTimeout?.invalidate()
            
            if let idleTimer = idlePingTimeout {
                idleTimer.invalidate()
                idlePingTimeout = nil
            }
            
            stream.disconnect()
            xmppStream = nil
            status = .offline
            presencesReady = false
            
            // Notify ConnectionManager
            NotificationCenter.default.post(
                name: NSNotification.Name("XMPPConnectionStatusChanged"),
                object: nil,
                userInfo: [
                    "status": "offline",
                    "reason": "Client disconnected"
                ]
            )
            // Clear presence response tracking when disconnecting
            clearPresenceResponseTracking()
            
            //NSlog("Client disconnected")
            //print("Client disconnected")
            logStep("disconnect")
        } catch {
            //NSlog("Error disconnecting client: %@", error.localizedDescription)
            //print("Error disconnecting client: \(error.localizedDescription)")
        }
    }
    
    internal func attachEventListeners() {
        guard xmppStream != nil else { return }
        
        // Event listeners are handled via XMPPStreamDelegate
        // The actual event handling happens in the XMPPStreamDelegate methods
    }
    
    // MARK: - Reconnection
    internal func scheduleReconnect(reason: String) {
        // Don't reconnect if connection was replaced
        if connectionReplaced {
            //NSlog("⚠️ Not scheduling reconnect - connection was replaced")
            //print("⚠️ Not scheduling reconnect - connection was replaced")
            return
        }
        
        if pausedDueToOfflineCap {
            //NSlog("⚠️ Not scheduling reconnect - offline cap reached")
            //print("⚠️ Not scheduling reconnect - offline cap reached")
            return
        }
        
        // Check cap
        if offlineReconnectAttempts >= maxOfflineReconnectAttempts {
            //NSlog("⚠️ Max offline reconnect attempts reached (%ld)", maxOfflineReconnectAttempts)
            //print("⚠️ Max offline reconnect attempts reached (\(maxOfflineReconnectAttempts))")
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
    
    internal func reconnect() async {
        presencesReady = false
        
        guard !reconnecting else { return }
        guard isBrowserOnline() else {
            logStep("reconnect:skipped-offline")
            return
        }
        
        //NSlog("Reconnecting...")
        //print("Reconnecting...")
        
        reconnecting = true
        defer { reconnecting = false }
        
        logStep("reconnect:start")
        await disconnect()
        initializeClient()
        logStep("reconnect:end")
    }
}
