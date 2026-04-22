//
//  WalletUsername.swift
//  XMPPChatCore
//
//  Utilities for deterministic XMPP localpart derivation.
//

import Foundation

public func walletToUsername(_ walletAddress: String) -> String {
    walletAddress
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "0x", with: "")
}
