//
//  ReceiptState.swift
//  XMPPChatUI
//
//  Tick state for an outgoing message. Mirrors web MessageBubble tickInfo:
//  seen beats delivered beats sent, and a pending or failed message shows no tick.
//

import Foundation
import XMPPChatCore

enum ReceiptState: Equatable {
    /// Pending or failed: no delivery tick.
    case none
    case sent
    case delivered
    case seen

    /// `watermarks` maps each member to the newest message id they displayed.
    /// A message is seen when some other member's watermark is at or after it.
    static func resolve(
        for message: Message,
        in messages: [Message],
        watermarks: [String: String],
        selfUsername: String
    ) -> ReceiptState {
        if message.pending == true || message.failed == true { return .none }

        let index = messages.firstIndex(where: { $0.id == message.id })
        if let index {
            let seen = watermarks.contains { user, watermarkId in
                guard !ReceiptPolicy.isSameUser(user, selfUsername) else { return false }
                guard let watermarkIndex = messages.firstIndex(where: {
                    $0.id == watermarkId || $0.xmppId == watermarkId
                }) else { return false }
                return watermarkIndex >= index
            }
            if seen { return .seen }
        }

        if !(message.receivedBy ?? [:]).isEmpty { return .delivered }
        return .sent
    }
}
