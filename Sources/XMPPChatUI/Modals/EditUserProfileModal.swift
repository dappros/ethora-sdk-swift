//
//  EditUserProfileModal.swift
//  XMPPChatUI
//
//  Edit user profile modal
//

import SwiftUI
import XMPPChatCore
#if os(iOS)
import UIKit
#endif

public struct EditUserProfileModal: View {
    let user: User
    let onUpdate: (User) -> Void
    let onClose: () -> Void
    
    @State private var firstName: String
    @State private var lastName: String
    @State private var description: String
    @State private var showImagePicker: Bool = false
    #if os(iOS)
    @State private var selectedImage: UIImage?
    #else
    @State private var selectedImage: NSImage?
    #endif
    @Environment(\.dismiss) var dismiss
    
    public init(
        user: User,
        onUpdate: @escaping (User) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.user = user
        self.onUpdate = onUpdate
        self.onClose = onClose
        self._firstName = State(initialValue: user.firstName ?? "")
        self._lastName = State(initialValue: user.lastName ?? "")
        self._description = State(initialValue: user.description ?? "")
    }
    
    public var body: some View {
        NavigationView {
            Form {
                Section("Profile Photo") {
                    Button(action: {
                        showImagePicker = true
                    }) {
                        HStack {
                            if let image = selectedImage {
                                #if os(iOS)
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                                #else
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                                #endif
                            } else if let imageURL = user.profileImage, let url = URL(string: imageURL) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    InitialsAvatarView(user: user)
                                }
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                            } else {
                                InitialsAvatarView(user: user)
                                    .frame(width: 80, height: 80)
                            }
                            
                            Text("Change Photo")
                                .foregroundColor(.blue)
                            Spacer()
                        }
                    }
                }
                
                Section("Personal Information") {
                    TextField("First Name", text: $firstName)
                    TextField("Last Name", text: $lastName)
                    if #available(iOS 16.0, macOS 13.0, *) {
                        TextField("Description", text: $description, axis: .vertical)
                            .lineLimit(3...6)
                    } else {
                        TextField("Description", text: $description)
                            .lineLimit(6)
                    }
                }
                
                Section {
                    Button(action: {
                        var updatedUser = user
                        // Update user properties
                        // This would need User to be mutable or use a builder pattern
                        onUpdate(updatedUser)
                        dismiss()
                    }) {
                        Text("Save Changes")
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Edit Profile")
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
            .sheet(isPresented: $showImagePicker) {
                #if os(iOS)
                ImagePicker(sourceType: .photoLibrary, mediaTypes: ["public.image"], onMediaSelected: { imageData, mimeType in
                    if let image = UIImage(data: imageData) {
                        selectedImage = image
                        // Upload image and update user
                    }
                })
                #endif
            }
        }
    }
}
