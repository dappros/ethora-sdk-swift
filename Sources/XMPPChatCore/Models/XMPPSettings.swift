//
//  XMPPSettings.swift
//  XMPPChatCore
//
//  Created from TypeScript models
//

import Foundation

public struct XMPPSettings: Codable, Equatable {
    /// Preferred key name for parity with Kotlin/Android config.
    public var xmppServerUrl: String?
    /// Legacy Swift key kept for backwards compatibility.
    public var devServer: String?
    public var host: String?
    public var conference: String?
    public var xmppPingOnSendEnabled: Bool?
    
    public init(
        xmppServerUrl: String? = nil,
        devServer: String? = nil,
        host: String? = nil,
        conference: String? = nil,
        xmppPingOnSendEnabled: Bool? = nil
    ) {
        let resolvedServer = xmppServerUrl ?? devServer
        self.xmppServerUrl = resolvedServer
        self.devServer = resolvedServer
        self.host = host
        self.conference = conference
        self.xmppPingOnSendEnabled = xmppPingOnSendEnabled
    }

    enum CodingKeys: String, CodingKey {
        case xmppServerUrl
        case devServer
        case host
        case conference
        case xmppPingOnSendEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let xmppServerUrl = try container.decodeIfPresent(String.self, forKey: .xmppServerUrl)
        let devServer = try container.decodeIfPresent(String.self, forKey: .devServer)

        let resolvedServer = xmppServerUrl ?? devServer
        self.xmppServerUrl = resolvedServer
        self.devServer = resolvedServer
        self.host = try container.decodeIfPresent(String.self, forKey: .host)
        self.conference = try container.decodeIfPresent(String.self, forKey: .conference)
        self.xmppPingOnSendEnabled = try container.decodeIfPresent(Bool.self, forKey: .xmppPingOnSendEnabled)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let server = xmppServerUrl ?? devServer
        try container.encodeIfPresent(server, forKey: .xmppServerUrl)
        try container.encodeIfPresent(server, forKey: .devServer)
        try container.encodeIfPresent(host, forKey: .host)
        try container.encodeIfPresent(conference, forKey: .conference)
        try container.encodeIfPresent(xmppPingOnSendEnabled, forKey: .xmppPingOnSendEnabled)
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
