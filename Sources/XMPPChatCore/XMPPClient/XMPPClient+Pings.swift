//
//  XMPPClient+Pings.swift
//  XMPPChatCore
//

import Foundation

extension XMPPClient {
    // MARK: - Activity Tracking
    internal func markActivity() {
        lastActivityTs = Date().timeIntervalSince1970
        scheduleAdaptivePing()
    }
    
    internal func scheduleAdaptivePing() {
        if idlePingTimeout != nil {
            idlePingTimeout?.invalidate()
        }
        
        let idleTime: TimeInterval = 2.0
        let pongWait: TimeInterval = 2.0
        
        idlePingTimeout = Timer.scheduledTimer(withTimeInterval: idleTime, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            guard self.status == .online && !self.pingInFlight else { return }
            
            // XMPP ping not wired here yet. Do not set pingInFlight without sending a ping:
            // it would stay true forever (no pong), and every later idle timer would bail on
            // the guard above — adaptive ping scheduling would stop after the first idle window.
            //
            // When implementing: set pingInFlight = true, send ping, set lastPingId; handlePong clears state.
            // let pingId = sendPing(self.xmppStream, self.host)
            // self.lastPingId = pingId
        }
    }
    
    // MARK: - Adaptive Ping
    internal func startAdaptivePing() {
        // This is already partially implemented, but we should match the exact logic
        scheduleAdaptivePing()
    }

    internal func isPong(_ stanza: XMPPStanza, pingId: String) -> Bool {
        // Check if stanza is a pong response to our ping
        return stanza.name == "iq" && 
               stanza.attributes["id"] == pingId &&
               stanza.attributes["type"] == "result"
    }

    internal func handlePong() {
        pingTimeout?.invalidate()
        pingTimeout = nil
        lastPingId = nil
        pingInFlight = false
    }
}
