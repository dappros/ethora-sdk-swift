//
//  ThreadView.swift
//  XMPPChatUI
//
//  Thread panel for a message and its replies. Mirrors web ThreadWrapper:
//  replies are the messages whose `mainMessage` parent is the root, the
//  composer sends one reply stanza ("Also send to" sets showInChannel), and
//  older pages are fetched from MAM until the root is reached.
//

import SwiftUI
import Combine
import XMPPChatCore

public struct ThreadView: View {
    let activeMessage: Message
    let currentUser: User
    let onClose: () -> Void
    let onSendMessage: (String, Bool) -> Void
    let onSendMedia: (Data, String) -> Void
    let customMessageComponent: ((MessageProps) -> AnyView)?
    let config: ChatConfig?
    /// Set by ChatRoomView: reactions go through the room view model.
    var onReact: ((String, String) -> Void)? = nil
    var currentReactorKey: String? = nil

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
        self.init(
            activeMessage: activeMessage,
            currentUser: currentUser,
            onClose: onClose,
            onSendMessage: onSendMessage,
            onSendMedia: onSendMedia,
            customMessageComponent: customMessageComponent,
            config: config,
            source: nil,
            onReact: nil,
            currentReactorKey: nil
        )
    }

    init(
        activeMessage: Message,
        currentUser: User,
        onClose: @escaping () -> Void,
        onSendMessage: @escaping (String, Bool) -> Void,
        onSendMedia: @escaping (Data, String) -> Void,
        customMessageComponent: ((MessageProps) -> AnyView)?,
        config: ChatConfig?,
        source: ChatRoomViewModel?,
        onReact: ((String, String) -> Void)?,
        currentReactorKey: String?
    ) {
        self.activeMessage = activeMessage
        self.currentUser = currentUser
        self.onClose = onClose
        self.onSendMessage = onSendMessage
        self.onSendMedia = onSendMedia
        self.customMessageComponent = customMessageComponent
        self.config = config
        self.onReact = onReact
        self.currentReactorKey = currentReactorKey
        self._viewModel = StateObject(wrappedValue: ThreadViewModel(
            roomJID: activeMessage.roomJid,
            activeMessage: activeMessage,
            source: source
        ))
    }

    public var body: some View {
        let settings = config ?? ChatConfig()
        VStack(spacing: 0) {
            // Thread Header
            ThreadHeaderView(
                message: viewModel.root,
                replyCount: viewModel.replyCount,
                onClose: onClose
            )

            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        // Original message
                        MessageBubbleView(
                            message: viewModel.root,
                            isUser: viewModel.root.user.id == currentUser.id,
                            showAvatar: false,
                            previousMessage: nil,
                            onLongPress: nil,
                            onRetry: nil,
                            onReactionTap: { emoji in onReact?(viewModel.root.id, emoji) },
                            onReply: nil,
                            onEdit: nil,
                            onDelete: nil,
                            onReport: nil,
                            onMediaTap: nil,
                            inThread: true,
                            currentReactorKey: currentReactorKey,
                            interactionsDisabled: settings.disableInteractions == true,
                            reactionsEnabled: ReactionSettings.enabled(settings),
                            reactionPickerEnabled: ReactionSettings.pickerEnabled(settings),
                            quickReactions: ReactionSettings.quickShortcodes(settings),
                            repliesEnabled: false,
                            accentColor: accent(settings)
                        )
                        .id("original-\(viewModel.root.id)")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal, 12)

                        // Replies
                        ForEach(viewModel.replies, id: \.id) { reply in
                            MessageBubbleView(
                                message: reply,
                                isUser: reply.user.id == currentUser.id,
                                showAvatar: false,
                                previousMessage: nil,
                                onLongPress: nil,
                                onRetry: nil,
                                onReactionTap: { emoji in onReact?(reply.id, emoji) },
                                onReply: nil,
                                onEdit: nil,
                                onDelete: nil,
                                onReport: nil,
                                onMediaTap: nil,
                                inThread: true,
                                currentReactorKey: currentReactorKey,
                                interactionsDisabled: settings.disableInteractions == true,
                                reactionsEnabled: ReactionSettings.enabled(settings),
                                reactionPickerEnabled: ReactionSettings.pickerEnabled(settings),
                                quickReactions: ReactionSettings.quickShortcodes(settings),
                                repliesEnabled: false,
                                accentColor: accent(settings)
                            )
                            .id(reply.id)
                            .padding(.horizontal, 12)
                            .fadeIn(duration: 0.2)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: viewModel.replies.count) { _ in
                    if let lastReply = viewModel.replies.last {
                        withAnimation {
                            proxy.scrollTo(lastReply.id, anchor: .bottom)
                        }
                    }
                }
            }

            // "Also send to room" checkbox
            AlsoSendToMainView(
                roomName: viewModel.roomName,
                isChecked: $alsoSendToMain,
                onRoomTap: onClose,
                primaryColor: settings.colors?.primary ?? "#0052CD"
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
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    private func accent(_ settings: ChatConfig) -> Color {
        Color(hex: settings.colors?.primary ?? "#0052CD")
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

// MARK: - Reply pill

/// The "N replies" pill under a root message (web BottomReplyContainer):
/// up to three reply authors as initials, then the count. Tapping opens the thread.
struct ThreadReplyPill: View {
    let replies: [Message]
    let isUser: Bool
    let accentColor: Color
    let onTap: () -> Void

    var body: some View {
        let users = uniqueUsers(replies)
        Button(action: onTap) {
            HStack(spacing: 6) {
                HStack(spacing: -6) {
                    ForEach(Array(users.prefix(3).enumerated()), id: \.offset) { _, user in
                        Text(initial(for: user))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color(.systemBackground)))
                            .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1))
                    }
                }
                if users.count > 3 {
                    Text("+\(users.count - 3)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text("\(replies.count) \(replies.count == 1 ? "reply" : "replies")")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(accentColor)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Capsule().fill(Color(.systemBackground)))
            .overlay(Capsule().stroke(Color.gray.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func uniqueUsers(_ replies: [Message]) -> [User] {
        var seen = Set<String>()
        var result: [User] = []
        for reply in replies where !seen.contains(reply.user.id) {
            seen.insert(reply.user.id)
            result.append(reply.user)
        }
        return result
    }

    private func initial(for user: User) -> String {
        let name = user.name ?? user.firstName ?? ""
        return name.first.map { String($0).uppercased() } ?? "?"
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

/// Replies and history paging for one thread. With a `source` view model the
/// replies come from its message list, which holds the MAM pages fetched so
/// far. Without one, they come from the RoomStore copy of the room.
@MainActor
final class ThreadViewModel: ObservableObject {
    /// Page size used by the web ThreadWrapper (THREAD_HISTORY_PAGE_SIZE).
    static let historyPageSize = 100

    @Published private(set) var replies: [Message] = []
    @Published private(set) var root: Message
    @Published var roomName: String = ""

    private let roomJID: String
    private let parentId: String
    private weak var source: ChatRoomViewModel?
    private var cancellables: Set<AnyCancellable> = []
    /// Cursor of the last page requested, so one page is never asked twice.
    private var lastRequestedBefore: Int64?

    var replyCount: Int { replies.count }

    init(roomJID: String, activeMessage: Message, source: ChatRoomViewModel? = nil) {
        self.roomJID = roomJID
        self.parentId = activeMessage.id
        self.root = activeMessage
        self.source = source
    }

    /// Starts following the replies and asks for the first older page.
    func start() {
        if let source {
            source.$messages
                .receive(on: RunLoop.main)
                .sink { [weak self] messages in
                    Task { @MainActor in
                        self?.refresh(from: messages)
                    }
                }
                .store(in: &cancellables)
        } else {
            refresh(from: RoomStore.shared.rooms[roomJID]?.messages ?? [])
        }
    }

    func stop() {
        cancellables.removeAll()
    }

    /// Re-derives the root and its replies from `messages`, then pages older
    /// history until the root's timestamp is reached or the archive ends.
    func refresh(from messages: [Message]) {
        let all = messages
        if let stored = all.first(where: { $0.id == parentId }) {
            root = stored
        }
        replies = ThreadReference.threadReplies(of: parentId, in: all)
        if let roomName = RoomStore.shared.rooms[roomJID]?.name ?? RoomStore.shared.rooms[roomJID]?.title {
            self.roomName = roomName
        }
        requestOlderPageIfNeeded(in: all)
    }

    private func requestOlderPageIfNeeded(in messages: [Message]) {
        guard let source else { return }
        guard let parentTimestamp = Int64(parentId) else { return }
        guard !messages.contains(where: { $0.id == parentId }) else { return }

        // Cursor: the oldest message id loaded for this room (MAM `before`).
        let ids = messages.compactMap { Int64($0.id) }
        guard let cursor = ids.min() else { return }
        guard cursor > parentTimestamp else { return }
        guard cursor != lastRequestedBefore else { return }

        lastRequestedBefore = cursor
        source.loadThreadHistory(before: cursor, max: Self.historyPageSize)
    }
}
