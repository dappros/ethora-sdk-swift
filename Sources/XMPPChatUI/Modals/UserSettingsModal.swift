//
//  UserSettingsModal.swift
//  XMPPChatUI
//
//  User settings modal
//

import SwiftUI
import XMPPChatCore

public struct UserSettingsModal: View {
    let user: User
    let onUpdate: (User) -> Void
    let onClose: () -> Void
    
    @State private var notificationsEnabled: Bool = true
    @State private var showProfileToEveryone: Bool = true
    @State private var showDeleteConfirmation: Bool = false
    @Environment(\.dismiss) var dismiss
    
    public init(
        user: User,
        onUpdate: @escaping (User) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.user = user
        self.onUpdate = onUpdate
        self.onClose = onClose
    }
    
    public var body: some View {
        NavigationView {
            Form {
                Section("Notifications") {
                    Toggle("Enable Notifications", isOn: $notificationsEnabled)
                }
                
                Section("Privacy") {
                    Toggle("Show Profile to Everyone", isOn: $showProfileToEveryone)
                }
                
                Section("Data Management") {
                    Button(action: {
                        // Export data
                    }) {
                        Text("Export My Data")
                    }
                    
                    Button(role: .destructive, action: {
                        showDeleteConfirmation = true
                    }) {
                        Text("Delete Account")
                    }
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .alert("Delete Account", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    // Handle account deletion
                }
            } message: {
                Text("Are you sure you want to delete your account? This action cannot be undone.")
            }
        }
    }
}
