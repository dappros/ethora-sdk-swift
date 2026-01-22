//
//  ThreadView.swift
//  XMPPChatUI
//
//  Thread view for message replies
//

import SwiftUI
import XMPPChatCore

public struct ThreadView: View {
    let activeMessage: Message
    let currentUser: User
    let onClose: () -> Void
    let onSendMessage: (String, Bool) -> Void
    let onSendMedia: (Data, String) -> Void
    let customMessageComponent: ((MessageProps) -> AnyView)?
    let config: ChatConfig?
    
    @StateObject private var viewModel: ThreadViewModel
    @State private var messageText: String = ""
    @State private var alsoSendToMain: Bool = false
    @FocusState private var isInputFocused: Bool
    
    public init(
        activeMessage: Message,
        currentUser: User,
        onClose: @escaping () -> Void,
        onSendMessage: @escaping (String, Bool) -> Void,
        onSendMedia: @escaping (Data, String) -> Void,
        customMessageComponent: ((MessageProps) -> AnyView)? = nil,
        config: ChatConfig? = nil
    ) {
        self.activeMessage = activeMessage
        self.currentUser = currentUser
        self.onClose = onClose
        self.onSendMessage = onSendMessage
        self.onSendMedia = onSendMedia
        self.customMessageComponent = customMessageComponent
        self.config = config
        self._viewModel = StateObject(wrappedValue: ThreadViewModel(roomJID: activeMessage.roomJid, activeMessage: activeMessage))
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Thread Header
            ThreadHeaderView(
                message: activeMessage,
                replyCount: viewModel.replyCount,
                onClose: onClose
            )
            
            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        // Original message
                        MessageBubble(
                            message: activeMessage,
                            isUser: activeMessage.user.id == currentUser.id,
                            isReply: false,
                            currentUserId: currentUser.id,
                            onReactionTap: nil,
                            onMessageTap: nil,
                            onLongPress: nil,
                            customComponent: customMessageComponent,
                            colors: config?.colors
                        )
                        .id("original-\(activeMessage.id)")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal, 12)
                        
                        // Replies
                        ForEach(viewModel.replies, id: \.id) { reply in
                            MessageBubble(
                                message: reply,
                                isUser: reply.user.id == currentUser.id,
                                isReply: true,
                                currentUserId: currentUser.id,
                                onReactionTap: nil,
                                onMessageTap: nil,
                                onLongPress: nil,
                                customComponent: customMessageComponent,
                                colors: config?.colors
                            )
                            .id(reply.id)
                            .padding(.horizontal, 12)
                            .fadeIn(duration: 0.2)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onAppear {
                    // Load replies when view appears
                    viewModel.loadReplies()
                    
                    if let lastReply = viewModel.replies.last {
                        withAnimation {
                            proxy.scrollTo(lastReply.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // "Also send to main chat" checkbox
            AlsoSendToMainView(
                roomName: viewModel.roomName,
                isChecked: $alsoSendToMain,
                onRoomTap: onClose,
                primaryColor: config?.colors?.primary ?? "#0052CD"
            )
            
            // Input Area
            HStack(spacing: 12) {
                Group {
                    if #available(iOS 16.0, macOS 13.0, *) {
                        TextField("Reply...", text: $messageText, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...5)
                    } else {
                        TextField("Reply...", text: $messageText)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(5)
                    }
                }
                .focused($isInputFocused)
                    .onSubmit {
                        if !messageText.isEmpty {
                            sendMessage()
                        }
                    }
                
                Button(action: {
                    sendMessage()
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(messageText.isEmpty ? .gray : .blue)
                }
                .disabled(messageText.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)
            .cornerRadius(15, corners: [.topLeft, .topRight])
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: -2)
        }
        .background(Color(red: 0.98, green: 0.98, blue: 0.99))
        .onAppear {
            viewModel.loadReplies()
        }
    }
    
    private func sendMessage() {
        guard !messageText.isEmpty else { return }
        let text = messageText
        messageText = ""
        onSendMessage(text, alsoSendToMain)
    }
}

// MARK: - Thread Header
struct ThreadHeaderView: View {
    let message: Message
    let replyCount: Int
    let onClose: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.title3)
                    .foregroundColor(.primary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Thread")
                    .font(.headline)
                Text("\(replyCount) \(replyCount == 1 ? "reply" : "replies")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 2)
    }
}

// MARK: - Also Send to Main
struct AlsoSendToMainView: View {
    let roomName: String
    @Binding var isChecked: Bool
    let onRoomTap: () -> Void
    let primaryColor: String
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                isChecked.toggle()
            }) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .foregroundColor(Color(hex: primaryColor))
            }
            
            Text("Also send to")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button(action: onRoomTap) {
                Text(roomName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Color(hex: primaryColor))
                    .underline()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.5))
    }
}

// MARK: - Thread ViewModel
@MainActor
class ThreadViewModel: ObservableObject {
    @Published var replies: [Message] = []
    @Published var replyCount: Int = 0
    @Published var roomName: String = ""
    
    private let roomJID: String
    private let activeMessage: Message
    
    init(roomJID: String, activeMessage: Message) {
        self.roomJID = roomJID
        self.activeMessage = activeMessage
    }
    
    func loadReplies() {
        // Load replies from RoomStore
        Task { @MainActor in
            // Get all messages for this room from RoomStore
            guard let room = RoomStore.shared.rooms[roomJID] else {
                //print("⚠️ ThreadViewModel: Room not found: \(roomJID)")
                return
            }
            
            let allMessages = room.messages
            
            // Filter messages where mainMessage == activeMessage.id
            let filteredReplies = allMessages.filter { message in
                message.mainMessage == activeMessage.id
            }
            
            // Sort by timestamp (oldest first)
            let sortedReplies = filteredReplies.sorted { msg1, msg2 in
                let ts1 = msg1.timestamp ?? 0
                let ts2 = msg2.timestamp ?? 0
                return ts1 < ts2
            }
            
            self.replies = sortedReplies
            self.replyCount = sortedReplies.count
            
            //print("📝 ThreadViewModel: Loaded \(sortedReplies.count) replies for message \(activeMessage.id)")
        }
    }
}
