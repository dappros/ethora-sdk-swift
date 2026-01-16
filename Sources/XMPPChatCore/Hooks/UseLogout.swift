//
//  UseLogout.swift
//  XMPPChatCore
//
//  Logout functionality
//

import Foundation

public class LogoutManager {
    public static let shared = LogoutManager()
    
    private init() {}
    
    public func logout(
        client: XMPPClient?,
        onCompletion: @escaping () -> Void
    ) {
        Task {
            // Disconnect XMPP
            await client?.disconnect()
            
            // Clear local storage
            LocalStorage.shared.clear()
            
            // Clear user data
            // This would be handled by UserStore
            
            await MainActor.run {
                onCompletion()
            }
        }
    }
    
    public func logoutWithConfirmation(
        client: XMPPClient?,
        showConfirmation: @escaping (@escaping (Bool) -> Void) -> Void,
        onCompletion: @escaping () -> Void
    ) {
        showConfirmation { confirmed in
            if confirmed {
                self.logout(client: client, onCompletion: onCompletion)
            }
        }
    }
}
