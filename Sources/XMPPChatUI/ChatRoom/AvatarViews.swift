//
//  AvatarViews.swift
//  XMPPChatUI
//

import SwiftUI
import XMPPChatCore

struct SizedAvatarView: View {
    let user: User
    let size: CGFloat
    
    var initials: String {
        let firstName = user.firstName ?? ""
        let lastName = user.lastName ?? ""
        let firstInitial = firstName.first.map(String.init) ?? ""
        let lastInitial = lastName.first.map(String.init) ?? ""
        return (firstInitial + lastInitial).uppercased()
    }
    
    @ViewBuilder
    var body: some View {        
        // Check if profileImage exists and is a valid URL
        if let photoURL = user.profileImage, 
           !photoURL.isEmpty, 
           photoURL.trimmingCharacters(in: .whitespacesAndNewlines) != "",
           let url = URL(string: photoURL),
           (url.scheme == "http" || url.scheme == "https") {
            // Show photo if available
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                case .failure(let error):
                    // Only log non-cancellation errors
                    let _ = {
                        if let urlError = error as? URLError, urlError.code != .cancelled {
                            print("⚠️ SizedAvatarView: Error loading avatar for user \(user.id): \(error.localizedDescription), URL: \(photoURL)")
                        }
                    }()
                    // Fallback to initials if image fails to load
                    InitialsAvatar(initials: initials, size: size)
                case .empty:
                    // Show loading placeholder
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: size, height: size)
                        ProgressView()
                            .scaleEffect(0.5)
                    }
                @unknown default:
                    InitialsAvatar(initials: initials, size: size)
                }
            }
        } else {
            // Show initials if no photo URL or invalid URL
            InitialsAvatar(initials: initials, size: size)
        }
    }
}

struct InitialsAvatar: View {
    let initials: String
    let size: CGFloat
    
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color.blue.opacity(0.7), Color.purple.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            
            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}
