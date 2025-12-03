//
//  UserStore.swift
//  XMPPChatCore
//
//  Simple user store for managing authentication state
//

import Foundation
import Combine

@MainActor
public class UserStore: ObservableObject {
    public static let shared = UserStore()
    
    @Published public var currentUser: User?
    @Published public var token: String?
    @Published public var refreshToken: String?
    @Published public var isAuthenticated: Bool = false
    
    private init() {
        // Load from defaults if available
        if let savedToken = UserDefaults.standard.string(forKey: "ethora_user_token"),
           let savedRefreshToken = UserDefaults.standard.string(forKey: "ethora_user_refresh_token"),
           let savedUserData = UserDefaults.standard.data(forKey: "ethora_user_data"),
           let user = try? JSONDecoder().decode(User.self, from: savedUserData) {
            self.token = savedToken
            self.refreshToken = savedRefreshToken
            self.currentUser = user
            self.isAuthenticated = true
        }
    }
    
    /// Set user data from login response
    public func setUser(from loginResponse: AuthAPI.LoginResponse) {
        // Convert UserResponse to User
        let user = User(
            id: loginResponse.user._id,
            name: "\(loginResponse.user.firstName ?? "") \(loginResponse.user.lastName ?? "")".trimmingCharacters(in: .whitespaces),
            token: loginResponse.token,
            refreshToken: loginResponse.refreshToken,
            walletAddress: loginResponse.user.defaultWallet?.walletAddress,
            firstName: loginResponse.user.firstName,
            lastName: loginResponse.user.lastName,
            email: loginResponse.user.email,
            profileImage: loginResponse.user.profileImage,
            username: loginResponse.user.username,
            xmppPassword: loginResponse.user.xmppPassword,
            xmppUsername: loginResponse.user.xmppUsername,
            isProfileOpen: loginResponse.user.isProfileOpen,
            isAssetsOpen: loginResponse.user.isAssetsOpen,
            isAgreeWithTerms: loginResponse.user.isAgreeWithTerms
        )
        
        self.currentUser = user
        self.token = loginResponse.token
        self.refreshToken = loginResponse.refreshToken
        self.isAuthenticated = true
        
        // Persist to UserDefaults
        UserDefaults.standard.set(loginResponse.token, forKey: "ethora_user_token")
        UserDefaults.standard.set(loginResponse.refreshToken, forKey: "ethora_user_refresh_token")
        if let userData = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(userData, forKey: "ethora_user_data")
        }
        
        print("✅ UserStore: User logged in - \(user.email ?? "unknown")")
    }
    
    /// Update tokens after refresh
    public func updateTokens(token: String, refreshToken: String) {
        self.token = token
        self.refreshToken = refreshToken
        UserDefaults.standard.set(token, forKey: "ethora_user_token")
        UserDefaults.standard.set(refreshToken, forKey: "ethora_user_refresh_token")
        print("✅ UserStore: Tokens refreshed")
    }
    
    /// Clear user data (logout)
    /// This removes all cached user data and tokens
    public func clearUser() {
        self.currentUser = nil
        self.token = nil
        self.refreshToken = nil
        self.isAuthenticated = false
        
        UserDefaults.standard.removeObject(forKey: "ethora_user_token")
        UserDefaults.standard.removeObject(forKey: "ethora_user_refresh_token")
        UserDefaults.standard.removeObject(forKey: "ethora_user_data")
        
        // Clear message cache on logout
        Task { @MainActor in
            MessageCache.shared.clearAll()
        }
        
        print("✅ UserStore: User logged out and cache cleared")
    }
    
    /// Check if user is cached (has valid token and user data)
    public var hasCachedUser: Bool {
        return isAuthenticated && currentUser != nil && token != nil
    }
}

