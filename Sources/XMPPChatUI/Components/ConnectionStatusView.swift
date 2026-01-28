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
