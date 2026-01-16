//
//  ConnectionStatusView.swift
//  XMPPChatUI
//
//  Connection status banner
//

import SwiftUI
import XMPPChatCore

public struct ConnectionStatusView: View {
    @ObservedObject var connectionManager: ConnectionManager
    
    public init(connectionManager: ConnectionManager) {
        self.connectionManager = connectionManager
    }
    
    public var body: some View {
        Group {
            switch connectionManager.status {
            case .connecting:
                StatusBanner(
                    message: "Connecting...",
                    color: .orange,
                    icon: "arrow.clockwise"
                )
            case .disconnected:
                StatusBanner(
                    message: "Disconnected",
                    color: .red,
                    icon: "exclamationmark.triangle.fill"
                )
            case .reconnecting:
                StatusBanner(
                    message: "Reconnecting...",
                    color: .orange,
                    icon: "arrow.clockwise"
                )
            case .connected:
                EmptyView()
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut, value: connectionManager.status)
    }
}

struct StatusBanner: View {
    let message: String
    let color: Color
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
            Text(message)
                .font(.subheadline)
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
            
            switch statusString {
            case "connected":
                self.status = .connected
            case "connecting":
                self.status = .connecting
            case "disconnected":
                self.status = .disconnected
            case "reconnecting":
                self.status = .reconnecting
            default:
                break
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
}
