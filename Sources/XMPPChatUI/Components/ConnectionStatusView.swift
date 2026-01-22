//
//  ConnectionStatusView.swift
//  XMPPChatUI
//
//  Connection status banner with user-friendly messages
//

import SwiftUI
import XMPPChatCore
import Network

public struct ConnectionStatusView: View {
    @ObservedObject var connectionManager: ConnectionManager
    @State private var hasInternetConnection: Bool = true
    
    public init(connectionManager: ConnectionManager) {
        self.connectionManager = connectionManager
    }
    
    public var body: some View {
        Group {
            switch connectionManager.status {
            case .connecting:
                StatusBanner(
                    message: connectionManager.disconnectReason ?? "Connecting to server...",
                    color: .orange,
                    icon: "arrow.clockwise",
                    isAnimated: true
                )
            case .disconnected:
                StatusBanner(
                    message: getUserFriendlyMessage(),
                    color: .red,
                    icon: getDisconnectIcon(),
                    isAnimated: false
                )
            case .reconnecting:
                StatusBanner(
                    message: connectionManager.disconnectReason ?? "Reconnecting...",
                    color: .orange,
                    icon: "arrow.clockwise",
                    isAnimated: true
                )
            case .connected:
                EmptyView()
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut, value: connectionManager.status)
        .onAppear {
            checkNetworkConnection()
        }
        .onChange(of: connectionManager.status) { _ in
            checkNetworkConnection()
        }
    }
    
    private func getUserFriendlyMessage() -> String {
        // Check internet connection first
        if !hasInternetConnection {
            return "No internet connection. Please check your network settings."
        }
        
        // Use specific disconnect reason if available
        if let reason = connectionManager.disconnectReason {
            return reason
        }
        
        // Default message
        return "Connection lost. Trying to reconnect..."
    }
    
    private func getDisconnectIcon() -> String {
        if !hasInternetConnection {
            return "wifi.slash"
        }
        return "exclamationmark.triangle.fill"
    }
    
    private func checkNetworkConnection() {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "NetworkMonitor")
        
        monitor.pathUpdateHandler = { path in
            Task { @MainActor in
                self.hasInternetConnection = path.status == .satisfied
                //print("🌐 ConnectionStatusView: Network status changed - hasInternet: \(self.hasInternetConnection)")
            }
        }
        
        monitor.start(queue: queue)
        
        // Stop monitoring after a short delay to avoid keeping it alive
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            monitor.cancel()
        }
    }
}

struct StatusBanner: View {
    let message: String
    let color: Color
    let icon: String
    let isAnimated: Bool
    
    init(message: String, color: Color, icon: String, isAnimated: Bool = false) {
        self.message = message
        self.color = color
        self.icon = icon
        self.isAnimated = isAnimated
    }
    
    var body: some View {
        HStack(spacing: 10) {
            if isAnimated {
                if #available(iOS 17.0, macOS 14.0, *) {
                    Image(systemName: icon)
                        .font(.caption)
                        .symbolEffect(.pulse, options: .repeating)
                } else {
                    Image(systemName: icon)
                        .font(.caption)
                }
            } else {
                Image(systemName: icon)
                    .font(.caption)
            }
            Text(message)
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(color)
    }
}

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
