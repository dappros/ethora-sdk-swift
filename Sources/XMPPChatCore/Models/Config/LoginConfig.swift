//
//  LoginConfig.swift
//  XMPPChatCore
//

import Foundation

public struct GoogleLoginConfig: Codable, Equatable {
    public let enabled: Bool
    public let firebaseConfig: FirebaseConfig
    
    public init(enabled: Bool, firebaseConfig: FirebaseConfig) {
        self.enabled = enabled
        self.firebaseConfig = firebaseConfig
    }
}

public struct JWTLoginConfig: Codable, Equatable {
    public let token: String
    public let enabled: Bool
    
    public init(token: String, enabled: Bool) {
        self.token = token
        self.enabled = enabled
    }
}

public struct UserLoginConfig: Codable, Equatable {
    public let enabled: Bool
    public let user: User?
    
    public init(enabled: Bool, user: User?) {
        self.enabled = enabled
        self.user = user
    }
}

public struct CustomLoginConfig {
    public let enabled: Bool
    public let loginFunction: () async throws -> User?
    
    public init(enabled: Bool, loginFunction: @escaping () async throws -> User?) {
        self.enabled = enabled
        self.loginFunction = loginFunction
    }
}
