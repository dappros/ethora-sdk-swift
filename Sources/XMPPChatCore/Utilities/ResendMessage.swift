//
//  ResendMessage.swift
//  XMPPChatCore
//
//  Resend failed message utility
//

import Foundation

public func resendMessage(
    message: Message,
    client: XMPPClient,
    user: User,
    completion: @escaping (Result<Message, Error>) -> Void
) {
    Task {
        do {
            if let mimetype = message.mimetype, mimetype.hasPrefix("media/") {
                // Resend media message
                if let location = message.location {
                    let mediaData = MediaMessageData(
                        firstName: user.firstName ?? "",
                        lastName: user.lastName ?? "",
                        walletAddress: user.walletAddress ?? "",
                        chatName: message.roomJid,
                        createdAt: String(Int64(message.date.timeIntervalSince1970 * 1000)),
                        fileName: message.fileName ?? "",
                        userId: user.id,
                        isVisible: true,
                        userAvatar: user.profileImage,
                        location: location,
                        mimetype: mimetype,
                        originalName: message.originalName,
                        size: message.size,
                        waveForm: message.waveForm,
                        isReply: message.isReply,
                        mainMessage: message.mainMessage,
                        roomJid: message.roomJid
                    )
                    
                    client.operations.sendMediaMessage(
                        roomJID: message.roomJid,
                        data: mediaData,
                        id: message.id
                    )
                    completion(.success(message))
                } else {
                    completion(.failure(NSError(domain: "ResendMessage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Media file not found"])))
                }
            } else {
                // Resend text message
                client.operations.sendTextMessage(
                    roomJID: message.roomJid,
                    firstName: user.firstName ?? "",
                    lastName: user.lastName ?? "",
                    photo: user.profileImage ?? "",
                    walletAddress: user.walletAddress ?? "",
                    userMessage: message.body,
                    isReply: message.isReply ?? false,
                    mainMessage: message.mainMessage
                )
                completion(.success(message))
            }
        } catch {
            completion(.failure(error))
        }
    }
}
