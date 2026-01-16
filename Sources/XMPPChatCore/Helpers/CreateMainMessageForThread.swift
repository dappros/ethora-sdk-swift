//
//  CreateMainMessageForThread.swift
//  XMPPChatCore
//
//  Create main message for thread
//

import Foundation

public func createMainMessageForThread(_ message: Message) -> [String: Any] {
    return [
        "id": message.id,
        "body": message.body,
        "user": [
            "id": message.user.id,
            "firstName": message.user.firstName ?? "",
            "lastName": message.user.lastName ?? ""
        ],
        "date": message.date.timeIntervalSince1970,
        "roomJid": message.roomJid
    ]
}
