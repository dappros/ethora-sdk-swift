//
//  E2EEConfig.swift
//  XMPPChatCore
//
//  End-to-end encryption switch, mirroring `config.e2ee` (IConfig.e2ee) on the web.
//

import Foundation

/// `ChatConfig.e2ee`. Off by default, and off changes nothing: no keys are generated and
/// stanzas are built exactly as before. With it on, messages in rooms the backend marked
/// `e2ee` are encrypted with OMEMO 2 (XEP-0384).
public struct E2EEConfig: Codable, Equatable {
    public var enabled: Bool

    public init(enabled: Bool) {
        self.enabled = enabled
    }
}
