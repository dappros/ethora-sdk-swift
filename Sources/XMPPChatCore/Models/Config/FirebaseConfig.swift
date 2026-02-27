//
//  FirebaseConfig.swift
//  XMPPChatCore
//

import Foundation

public struct FirebaseConfig: Codable, Equatable {
    public let apiKey: String
    public let authDomain: String
    public let projectId: String
    public let storageBucket: String
    public let messagingSenderId: String
    public let appId: String
    
    public init(
        apiKey: String,
        authDomain: String,
        projectId: String,
        storageBucket: String,
        messagingSenderId: String,
        appId: String
    ) {
        self.apiKey = apiKey
        self.authDomain = authDomain
        self.projectId = projectId
        self.storageBucket = storageBucket
        self.messagingSenderId = messagingSenderId
        self.appId = appId
    }
}
