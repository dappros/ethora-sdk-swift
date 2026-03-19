//
//  XMPPClient+Stream.swift
//  XMPPChatCore
//

import Foundation

// MARK: - XMPPStreamDelegate
extension XMPPClient: XMPPStreamDelegate {
    public func xmppStreamDidConnect(_ stream: XMPPStream) {
        status = .connecting
        logStep("event:connecting")
            // Notify ConnectionManager
            NotificationCenter.default.post(
                name: NSNotification.Name("XMPPConnectionStatusChanged"),
                object: nil,
                userInfo: [
                    "status": "connecting",
                    "reason": "Connecting to server..."
                ]
            )
    }
    
    // This should be called when XMPP stream becomes online
    public func xmppStreamDidBecomeOnline(_ stream: XMPPStream, jid: String) {
        Task {
            await handleOnlineEvent(jid: jid)
        }
    }
    
    internal func handleOnlineEvent(jid: String) async {
        // Extract resource from JID: user@host/resource
        if let resourcePart = jid.components(separatedBy: "/").last, !resourcePart.isEmpty {
            resource = resourcePart
        } else {
            resource = "default"
        }
        
        status = .online
        isConnecting = false // Connection successful, reset flag
            
            // Notify ConnectionManager
            NotificationCenter.default.post(
                name: NSNotification.Name("XMPPConnectionStatusChanged"),
                object: nil,
                userInfo: ["status": "connected"]
            )
            
            reconnectAttempts = 0
            
            offlineReconnectAttempts = 0
            
            pausedDueToOfflineCap = false
            
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
            
            // IMPORTANT: Send simple presence to XMPP server first (announcing online status)
            let presenceStanza = XMPPStanza(name: "presence")
            xmppStream?.send(presenceStanza)
            
            // Wait a bit for the server to process the initial presence
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            await sendAllPresencesAndMarkReady()
            
            logStep("event:online")
            
        Task {
            await processQueue()
        }
    }
    
    public func xmppStreamDidDisconnect(_ stream: XMPPStream, error: Error?) {
        
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
        
        // Prepare disconnect reason for user-friendly message
        var disconnectReason: String? = nil
        var errorCode: Int? = nil
        var errorDescription: String? = nil
        
        if let error = error {
            if let nsError = error as NSError? {
                errorCode = nsError.code
                errorDescription = nsError.localizedDescription
                
                // Format user-friendly reason
                if wasReplaced {
                    disconnectReason = "Another device is connected"
                } else if let code = nsError.userInfo["disconnectCode"] as? UInt16 {
                    switch code {
                    case 1000:
                        disconnectReason = "Connection closed normally"
                    case 1001:
                        disconnectReason = "Server is going away"
                    case 1008:
                        disconnectReason = "Policy violation"
                    case 1011:
                        disconnectReason = "Server error. Please try again later"
                    default:
                        disconnectReason = "Connection error (code: \(code))"
                    }
                } else if nsError.code == 409 {
                    disconnectReason = "Another device is connected"
                } else if nsError.domain == "XMPPStream" {
                    disconnectReason = "Server connection lost"
                } else {
                    disconnectReason = nsError.localizedDescription
                }
            }
        } else {
            // No error provided - generic disconnect
            if wasReplaced {
                disconnectReason = "Another device is connected"
            } else {
                disconnectReason = "Connection lost"
            }
        }
        
        // Notify ConnectionManager with detailed information
        var userInfo: [String: Any] = ["status": "disconnected"]
        if let reason = disconnectReason {
            userInfo["reason"] = reason
        }
        if let code = errorCode {
            userInfo["errorCode"] = code
        }
        if let description = errorDescription {
            userInfo["errorDescription"] = description
        }
        
        NotificationCenter.default.post(
            name: NSNotification.Name("XMPPConnectionStatusChanged"),
            object: nil,
            userInfo: userInfo
        )
        pingInterval?.invalidate()
        isConnecting = false // Reset connection flag on disconnect
        
        // Only schedule reconnect if connection wasn't replaced
        if wasReplaced || connectionReplaced {
            connectionReplaced = false // Reset flag
        } else {
            scheduleReconnect(reason: "event:disconnect")
        }
    }
    
    public func xmppStream(_ stream: XMPPStream, didReceiveStanza stanza: XMPPStanza) {
        lastActivityTs = Date().timeIntervalSince1970
        
        if let pingId = lastPingId, isPong(stanza, pingId: pingId) {
            handlePong()
        }
        
        handleStanza(stanza)
        
        // Also notify delegate
        delegate?.xmppClient(self, didReceiveStanza: stanza)
    }
    
    public func xmppStream(_ stream: XMPPStream, didSendStanza stanza: XMPPStanza) {
        // Stanza sent
    }
    
    // Handle error event
    public func xmppStream(_ stream: XMPPStream, didReceiveError error: Error) {
        status = .error
        logStep("event:error")
        
        // Prepare error information for user-friendly message
        var userInfo: [String: Any] = ["status": "disconnected"]
        var reason: String = "Server error occurred"
        
        if let nsError = error as NSError? {
            if nsError.domain == "XMPPStream" {
                reason = "Connection error. Please try again."
            } else {
                reason = nsError.localizedDescription
            }
            userInfo["errorCode"] = nsError.code
            userInfo["errorDescription"] = nsError.localizedDescription
        }
        
        userInfo["reason"] = reason
        
        // Notify ConnectionManager
        NotificationCenter.default.post(
            name: NSNotification.Name("XMPPConnectionStatusChanged"),
            object: nil,
            userInfo: userInfo
        )
        scheduleReconnect(reason: "event:error")
    }
}
