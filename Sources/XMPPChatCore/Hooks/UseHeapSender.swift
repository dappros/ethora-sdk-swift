//
//  UseHeapSender.swift
//  XMPPChatCore
//
//  Message heap sending
//

import Foundation

@MainActor
public class HeapSender: ObservableObject {
    @Published public var sendingMessages: [String: Bool] = [:] // messageId: isSending
    
    public func sendHeapMessage(
        message: Message,
        client: XMPPClient,
        user: User,
        completion: @escaping (Result<Message, Error>) -> Void
    ) {
        sendingMessages[message.id] = true
        
        Task {
            do {
                if let mimetype = message.mimetype, mimetype.hasPrefix("media/") {
                    if let location = message.location {
                        // Create MediaMessageData from message
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
                    }
                } else {
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
                }
                
                await MainActor.run {
                    sendingMessages[message.id] = false
                    completion(.success(message))
                }
            } catch {
                await MainActor.run {
                    sendingMessages[message.id] = false
                    completion(.failure(error))
                }
            }
        }
    }
    
    public func batchSendMessages(
        messages: [Message],
        client: XMPPClient,
        user: User,
        completion: @escaping ([Result<Message, Error>]) -> Void
    ) {
        Task {
            var results: [Result<Message, Error>] = []
            
            for message in messages {
                await withTaskGroup(of: Result<Message, Error>.self) { group in
                    group.addTask {
                        await self.sendSingleMessage(message: message, client: client, user: user)
                    }
                    
                    for await result in group {
                        results.append(result)
                    }
                }
            }
            
            await MainActor.run {
                completion(results)
            }
        }
    }
    
    private func sendSingleMessage(message: Message, client: XMPPClient, user: User) async -> Result<Message, Error> {
        do {
            if let mimetype = message.mimetype, mimetype.hasPrefix("media/") {
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
                }
            } else {
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
            }
            return .success(message)
        } catch {
            return .failure(error)
        }
    }
}
