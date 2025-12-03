//
//  XMPPClient+Operations.swift
//  XMPPChatCore
//
//  Extension for operations access
//

import Foundation

extension XMPPClient {
    public var operations: XMPPOperations {
        return XMPPOperations(client: self)
    }
}

