//
//  ConnectionManager.swift
//  XMPPChatCore
//
//  Connection status manager for XMPP client
//

import Foundation
import Combine

// MARK: - Connection Manager
@MainActor
public class ConnectionManager: ObservableObject {
    @Published public var status: ConnectionStatus = .disconnected
    @Published public var disconnectReason: String? = nil
    
    public enum ConnectionStatus {
        case connected
        case connecting
        case disconnected
        case reconnecting
    }
    
    public static let shared = ConnectionManager()
    
    private var notificationObserver: NSObjectProtocol?
    
    public init() {
        // Listen for XMPP connection status changes
        notificationObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("XMPPConnectionStatusChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let statusString = userInfo["status"] as? String else {
                return
            }
            
            // Extract disconnect reason if available
            let reason = userInfo["reason"] as? String
            let errorCode = userInfo["errorCode"] as? Int
            let errorDescription = userInfo["errorDescription"] as? String
            
            // Log connection status change for debugging
            //print("🔌 ConnectionManager: Status changed to '\(statusString)'")
            if let reason = reason {
                //print("   Reason: \(reason)")
            }
            if let errorCode = errorCode {
                //print("   Error Code: \(errorCode)")
            }
            if let errorDescription = errorDescription {
                //print("   Error Description: \(errorDescription)")
            }
            
            Task { @MainActor in
                switch statusString {
                case "connected":
                    self.status = .connected
                    self.disconnectReason = nil
                    //print("✅ ConnectionManager: Connected successfully")
                case "connecting":
                    self.status = .connecting
                    self.disconnectReason = reason ?? "Connecting to server..."
                    //print("🔄 ConnectionManager: Connecting...")
                case "disconnected":
                    self.status = .disconnected
                    self.disconnectReason = self.formatDisconnectReason(
                        reason: reason,
                        errorCode: errorCode,
                        errorDescription: errorDescription
                    )
                    //print("❌ ConnectionManager: Disconnected - \(self.disconnectReason ?? "Unknown reason")")
                case "reconnecting":
                    self.status = .reconnecting
                    self.disconnectReason = reason ?? "Reconnecting..."
                    //print("🔄 ConnectionManager: Reconnecting...")
                default:
                    break
                }
            }
        }
    }
    
    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    public func updateStatus(_ newStatus: ConnectionStatus) {
        status = newStatus
    }
    
    private func formatDisconnectReason(reason: String?, errorCode: Int?, errorDescription: String?) -> String? {
        // If we have a specific reason, use it
        if let reason = reason, !reason.isEmpty {
            return reason
        }
        
        // Format based on error code
        if let code = errorCode {
            switch code {
            case 409:
                return "Another device is connected. This connection will close."
            case 1000:
                return "Connection closed normally."
            case 1001:
                return "Server is going away."
            case 1006:
                return "Connection lost. Check your internet connection."
            case 1008:
                return "Policy violation. Connection closed."
            case 1011:
                return "Server error. Please try again later."
            default:
                if let description = errorDescription {
                    return description
                }
                return "Connection error (code: \(code))"
            }
        }
        
        // Use error description if available
        if let description = errorDescription, !description.isEmpty {
            return description
        }
        
        return nil // Will use default message in view
    }
}
