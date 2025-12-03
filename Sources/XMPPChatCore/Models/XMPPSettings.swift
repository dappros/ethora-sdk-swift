//
//  XMPPSettings.swift
//  XMPPChatCore
//
//  Created from TypeScript models
//

import Foundation

public struct XMPPSettings: Codable, Equatable {
    public var devServer: String?
    public var host: String?
    public var conference: String?
    public var xmppPingOnSendEnabled: Bool?
    
    public init(
        devServer: String? = nil,
        host: String? = nil,
        conference: String? = nil,
        xmppPingOnSendEnabled: Bool? = nil
    ) {
        self.devServer = devServer
        self.host = host
        self.conference = conference
        self.xmppPingOnSendEnabled = xmppPingOnSendEnabled
    }
}

public enum ConnectionStatus: String {
    case offline = "offline"
    case connecting = "connecting"
    case online = "online"
    case error = "error"
}

public struct ConnectionStep: Codable, Equatable {
    public let timestamp: Int64
    public let step: String
    
    public init(timestamp: Int64, step: String) {
        self.timestamp = timestamp
        self.step = step
    }
}

