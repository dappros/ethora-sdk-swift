//
//  RoomSettingsModal.swift
//  XMPPChatUI
//
//  Room settings modal
//

import SwiftUI
import XMPPChatCore

public struct RoomSettingsModal: View {
    let room: Room
    let onUpdate: (Room) -> Void
    let onDelete: () -> Void
    let onClose: () -> Void
    
    @State private var roomName: String
    @State private var roomDescription: String
    @State private var showDeleteConfirmation: Bool = false
    @Environment(\.dismiss) var dismiss
    
    public init(
        room: Room,
        onUpdate: @escaping (Room) -> Void,
        onDelete: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.room = room
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self.onClose = onClose
        self._roomName = State(initialValue: room.name ?? "")
        self._roomDescription = State(initialValue: room.description ?? "")
    }
    
    public var body: some View {
        NavigationView {
            Form {
                Section("Room Information") {
                    TextField("Room Name", text: $roomName)
                    if #available(iOS 16.0, macOS 13.0, *) {
                        TextField("Description", text: $roomDescription, axis: .vertical)
                            .lineLimit(3...6)
                    } else {
                        TextField("Description", text: $roomDescription)
                            .lineLimit(6)
                    }
                }
                
                Section("Actions") {
                    Button(action: {
                        var updatedRoom = room
                        // Update room properties
                        onUpdate(updatedRoom)
                        dismiss()
                    }) {
                        Text("Save Changes")
                            .foregroundColor(.blue)
                    }
                    
                    Button(role: .destructive, action: {
                        showDeleteConfirmation = true
                    }) {
                        Text("Delete Room")
                    }
                }
            }
            .navigationTitle("Room Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Delete Room", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to delete this room? This action cannot be undone.")
            }
        }
    }
}
