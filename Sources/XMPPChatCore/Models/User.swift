//
//  User.swift
//  XMPPChatCore
//
//  Created from TypeScript models
//

import Foundation

public struct User: Codable, Identifiable, Equatable {
    public let id: String
    public var name: String?
    public var userJID: String?
    public var token: String?
    public var refreshToken: String?
    public var walletAddress: String?
    public var description: String?
    public var firstName: String?
    public var lastName: String?
    public var email: String?
    public var profileImage: String?
    public var username: String?
    public var xmppPassword: String?
    public var xmppUsername: String?
    public var langSource: String?
    public var homeScreen: String?
    public var registrationChannelType: String?
    public var updatedAt: String?
    public var authMethod: String?
    public var roles: [String]?
    public var tags: [String]?
    public var isProfileOpen: Bool?
    public var isAssetsOpen: Bool?
    public var isAgreeWithTerms: Bool?
    public var isSuperAdmin: Bool?
    
    public init(
        id: String,
        name: String? = nil,
        userJID: String? = nil,
        token: String? = nil,
        refreshToken: String? = nil,
        walletAddress: String? = nil,
        description: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        email: String? = nil,
        profileImage: String? = nil,
        username: String? = nil,
        xmppPassword: String? = nil,
        xmppUsername: String? = nil,
        langSource: String? = nil,
        homeScreen: String? = nil,
        registrationChannelType: String? = nil,
        updatedAt: String? = nil,
        authMethod: String? = nil,
        roles: [String]? = nil,
        tags: [String]? = nil,
        isProfileOpen: Bool? = nil,
        isAssetsOpen: Bool? = nil,
        isAgreeWithTerms: Bool? = nil,
        isSuperAdmin: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.userJID = userJID
        self.token = token
        self.refreshToken = refreshToken
        self.walletAddress = walletAddress
        self.description = description
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.profileImage = profileImage
        self.username = username
        self.xmppPassword = xmppPassword
        self.xmppUsername = xmppUsername
        self.langSource = langSource
        self.homeScreen = homeScreen
        self.registrationChannelType = registrationChannelType
        self.updatedAt = updatedAt
        self.authMethod = authMethod
        self.roles = roles
        self.tags = tags
        self.isProfileOpen = isProfileOpen
        self.isAssetsOpen = isAssetsOpen
        self.isAgreeWithTerms = isAgreeWithTerms
        self.isSuperAdmin = isSuperAdmin
    }
    
    public var fullName: String {
        if let firstName = firstName, let lastName = lastName {
            return "\(firstName) \(lastName)"
        }
        return name ?? username ?? id
    }
}

