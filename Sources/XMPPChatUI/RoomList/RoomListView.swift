//
//  RoomListView.swift
//  XMPPChatUI
//
//  Room List component
//

import SwiftUI
import XMPPChatCore

// Helper wrapper to create ChatRoomViewModel with callback
private struct ChatRoomViewWrapper: View {
    @Binding var room: Room
    let client: XMPPClient
    let currentUserId: String
    let onMessagesUpdated: (Room) -> Void
    
    @StateObject private var viewModel: ChatRoomViewModel
    
    init(room: Binding<Room>, client: XMPPClient, currentUserId: String, onMessagesUpdated: @escaping (Room) -> Void) {
        self._room = room
        self.client = client
        self.currentUserId = currentUserId
        self.onMessagesUpdated = onMessagesUpdated
        
        // Create the view model with the initial room
        _viewModel = StateObject(wrappedValue: ChatRoomViewModel(
            room: room.wrappedValue,
            client: client,
            currentUserId: currentUserId,
            config: ConfigStore.shared.config
        ))
    }
    
    var body: some View {
        ChatRoomView(viewModel: viewModel)
            .onAppear {
                // Set up callback when view appears
                viewModel.onMessagesUpdated = onMessagesUpdated
            }
    }
}

public struct RoomListView: View {
    @ObservedObject var viewModel: RoomListViewModel
    private let singleRoomJID: String?
    private let hideRoomList: Bool
    @State private var searchText: String = ""
    /// Programmatic navigation when opening a room from a push (RN `PENDING_NOTIFICATION_JID_KEY` flow).
    @State private var pushNavActive: Bool = false
    @State private var pushNavRoomBareJID: String?
    
    public init(viewModel: RoomListViewModel, singleRoomJID: String? = nil, hideRoomList: Bool = false) {
        self.viewModel = viewModel
        self.singleRoomJID = singleRoomJID
        self.hideRoomList = hideRoomList
    }
    
    public var body: some View {
        NavigationView {
            Group {
                if hideRoomList {
                    singleRoomContent
                } else {
                    roomListContent
                }
            }
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.4), Color.black.opacity(0.85)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .modifier(RoomListModeModifier(hideRoomList: hideRoomList, searchText: $searchText, viewModel: viewModel))
            .background(pushNavigationLink)
            .onAppear {
                // Call loadRooms if not already loading
                if !viewModel.isLoading && viewModel.rooms.isEmpty {
                    viewModel.loadRooms()
                }
                tryOpenRoomFromPendingPushNotification()
            }
            .onReceive(viewModel.$rooms) { _ in
                tryOpenRoomFromPendingPushNotification()
            }
            .onChange(of: viewModel.isLoading) { loading in
                if !loading {
                    tryOpenRoomFromPendingPushNotification()
                }
            }
        }
    }
    
    @ViewBuilder
    private var roomListContent: some View {
        List {
            if filteredRooms.isEmpty {
                if viewModel.isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading rooms…")
                    }
                } else if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                } else {
                    Text("No rooms loaded")
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(filteredRooms) { room in
                    NavigationLink(destination: destinationView(for: room)) {
                        RoomListItemView(
                            room: room,
                            currentUserId: viewModel.currentUserId,
                            messages: room.messages
                        )
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var singleRoomContent: some View {
        if let room = matchedSingleRoom {
            destinationView(for: room)
        } else if viewModel.isLoading {
            VStack(spacing: 10) {
                ProgressView()
                Text("Loading selected chat...")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let wanted = normalizedSingleRoomBareJID {
            VStack(spacing: 10) {
                Text("Selected chat was not found.")
                    .font(.headline)
                Text("Room: \(wanted)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 10) {
                Text("Single chat mode is enabled, but Room JID is empty.")
                    .font(.headline)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var normalizedSingleRoomBareJID: String? {
        guard let singleRoomJID else { return nil }
        let trimmed = singleRoomJID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.components(separatedBy: "/").first
    }
    
    private var matchedSingleRoom: Room? {
        guard let target = normalizedSingleRoomBareJID?.lowercased() else { return nil }
        return viewModel.rooms.first { room in
            let bare = (room.jid.components(separatedBy: "/").first ?? room.jid).lowercased()
            return bare == target
        }
    }

    private var pushNavigationLink: some View {
        NavigationLink(
            destination: pushNavigationDestination,
            isActive: Binding(
                get: { pushNavActive },
                set: { newValue in
                    pushNavActive = newValue
                    if !newValue { pushNavRoomBareJID = nil }
                }
            )
        ) {
            EmptyView()
        }
        .hidden()
    }

    @ViewBuilder
    private var pushNavigationDestination: some View {
        if let bare = pushNavRoomBareJID,
           let room = viewModel.rooms.first(where: {
               ($0.jid.components(separatedBy: "/").first ?? $0.jid).caseInsensitiveCompare(bare) == .orderedSame
           }) {
            destinationView(for: room)
        } else {
            EmptyView()
        }
    }

    private func tryOpenRoomFromPendingPushNotification() {
        guard let bare = viewModel.pendingPushRoomJIDToOpen() else { return }
        pushNavRoomBareJID = bare
        pushNavActive = true
    }
    
    private var filteredRooms: [Room] {
        let rooms = if searchText.isEmpty {
            viewModel.rooms
        } else {
            viewModel.rooms.filter { room in
                room.title.localizedCaseInsensitiveContains(searchText) ||
                room.lastMessage?.body.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
        
        // Sort by last message timestamp (most recent first)
        return rooms.sorted { room1, room2 in
            let timestamp1 = getLastMessageTimestamp(for: room1)
            let timestamp2 = getLastMessageTimestamp(for: room2)
            return timestamp1 > timestamp2 // Most recent first
        }
    }
    
    /// Get the timestamp of the last message for a room
    private func getLastMessageTimestamp(for room: Room) -> Int64 {
        // First try to get timestamp from last message in messages array
        if let lastMessage = room.messages.last,
           let timestamp = lastMessage.timestamp {
            return timestamp
        }
        // Fallback to lastMessageTimestamp property
        if let timestamp = room.lastMessageTimestamp {
            return timestamp
        }
        // If no timestamp, use 0 (will appear at bottom)
        return 0
    }
    
    @ViewBuilder
    private func destinationView(for room: Room) -> some View {
        // Find the current room from viewModel to get updated messages
        let currentRoom = viewModel.rooms.first(where: { $0.jid == room.jid }) ?? room
        
        // Create a binding to update the room when messages change
        let binding = Binding<Room>(
            get: { 
                viewModel.rooms.first(where: { $0.jid == room.jid }) ?? room
            },
            set: { updatedRoom in
                if let index = viewModel.rooms.firstIndex(where: { $0.jid == updatedRoom.jid }) {
                    viewModel.rooms[index] = updatedRoom
                }
            }
        )
        
        ChatRoomViewWrapper(
            room: binding,
            client: viewModel.client,
            currentUserId: viewModel.currentUserId,
            onMessagesUpdated: { updatedRoom in
                if let index = viewModel.rooms.firstIndex(where: { $0.jid == updatedRoom.jid }) {
                    viewModel.rooms[index] = updatedRoom
                }
            }
        )
    }
}

private struct RoomListModeModifier: ViewModifier {
    let hideRoomList: Bool
    @Binding var searchText: String
    @ObservedObject var viewModel: RoomListViewModel

    func body(content: Content) -> some View {
        if hideRoomList {
            content.navigationTitle("Chat")
        } else {
            content
                .searchable(text: $searchText)
                .navigationTitle("Chats")
                .toolbar {
                    #if os(iOS)
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            viewModel.showNewChatModal = true
                        }) {
                            Image(systemName: "plus")
                        }
                    }
                    #else
                    ToolbarItem(placement: .automatic) {
                        Button(action: {
                            viewModel.showNewChatModal = true
                        }) {
                            Image(systemName: "plus")
                        }
                    }
                    #endif
                }
                .sheet(isPresented: $viewModel.showNewChatModal) {
                    NewChatModal(
                        availableUsers: viewModel.getAvailableUsers(),
                        onCreateChat: { chatName, description, users in
                            Task { @MainActor in
                                do {
                                    if users.count == 1, let user = users.first {
                                        try await viewModel.createPrivateRoom(with: user)
                                    } else {
                                        try await viewModel.createRoom(
                                            title: chatName,
                                            description: description ?? "",
                                            members: users
                                        )
                                    }
                                    viewModel.showNewChatModal = false
                                } catch {
                                    viewModel.errorMessage = error.localizedDescription
                                }
                            }
                        },
                        onClose: {
                            viewModel.showNewChatModal = false
                        }
                    )
                }
        }
    }
}

// MARK: - Room List Item
struct RoomListItemView: View {
    let room: Room
    let currentUserId: String
    let messages: [Message]
    
    var body: some View {
        HStack(spacing: 12) {
            // Room Icon
            if let icon = room.icon, let url = URL(string: icon) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(room.title.prefix(1).uppercased())
                            .font(.headline)
                            .foregroundColor(.blue)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(room.title)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Show timestamp from last message if available
                    if let lastMessage = getLastMessage(from: room),
                       let timestamp = lastMessage.timestamp {
                        Text(timeString(from: timestamp))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let timestamp = room.lastMessageTimestamp {
                        Text(timeString(from: timestamp))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    // Check if there's an active typing indicator (pending state)
                    if isTypingActive {
                        // Show typing indicator instead of last message
                        Text(typingIndicatorText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .italic()
                            .lineLimit(1)
                    } else {
                        // Show last message if no typing indicator
                        showLastMessage()
                    }
                    
                    Spacer()
                    
                    if room.unreadMessages > 0 {
                        Text("\(room.unreadMessages)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.blue)
                            .clipShape(Circle())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    // Check if typing indicator is active
    private var isTypingActive: Bool {
        guard let composingList = room.composingList,
              !composingList.isEmpty,
              room.composing == true else {
            return false
        }
        return !getTypingUserNames(from: composingList).isEmpty
    }
    
    // Get typing indicator text
    private var typingIndicatorText: String {
        guard let composingList = room.composingList else {
            return ""
        }
        let typingNames = getTypingUserNames(from: composingList)
        return typingText(from: typingNames)
    }
    
    private func getInitials(for title: String) -> String {
        let parts = title.components(separatedBy: " ")
        if parts.count > 1, let first = parts.first?.first, let last = parts.last?.first {
            return "\(first)\(last)".uppercased()
        } else if let first = title.first {
            return String(first).uppercased()
        }
        return "?"
    }
    
    /// Get the last message from room's messages array or lastMessage property
    private func getLastMessage(from room: Room) -> Message? {
        // First check if room has messages in the messages array
        if let lastMessage = room.messages.last {
            return lastMessage
        }
        // Fallback to lastMessage property if available
        // Note: LastMessage might need to be converted to Message if different types
        return nil
    }
    
    // Get user names from composing user IDs (similar to ChatHeaderView)
    private func getTypingUserNames(from composingList: [String]) -> [String] {
        // Filter out current user
        let filteredUsers = composingList.filter { userId in
            let normalizedUserId = userId.lowercased().trimmingCharacters(in: .whitespaces)
            let normalizedCurrentId = currentUserId.lowercased().trimmingCharacters(in: .whitespaces)
            return normalizedUserId != normalizedCurrentId
        }
        
        // Get user names from room.members first, then from messages as fallback
        return filteredUsers.compactMap { userId in
            // First try to find in room.members
            if let members = room.members {
                if let member = members.first(where: { member in
                    let normalizedMemberId = member.id.lowercased().trimmingCharacters(in: .whitespaces)
                    let normalizedMemberXmpp = member.xmppUsername?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
                    let normalizedUserId = userId.lowercased().trimmingCharacters(in: .whitespaces)
                    
                    return normalizedMemberId == normalizedUserId ||
                           normalizedMemberXmpp == normalizedUserId ||
                           member.jid?.lowercased() == normalizedUserId
                }) {
                    // Use name, or firstName + lastName, or firstName, or lastName, or xmppUsername as fallback
                    if let name = member.name, !name.isEmpty {
                        return name
                    } else if let firstName = member.firstName, let lastName = member.lastName {
                        return "\(firstName) \(lastName)"
                    } else if let firstName = member.firstName {
                        return firstName
                    } else if let lastName = member.lastName {
                        return lastName
                    } else if let xmppUsername = member.xmppUsername {
                        return xmppUsername
                    }
                }
            }
            
            // Fallback: try to find user in messages
            if let message = messages.first(where: {
                $0.user.id == userId ||
                $0.user.xmppUsername?.lowercased() == userId.lowercased() ||
                $0.user.xmppUsername?.lowercased() == userId.lowercased().components(separatedBy: "@").first
            }) {
                return message.user.fullName
            }
            
            // Last fallback: return userId (shouldn't happen normally)
            return userId
        }
    }
    
    // Generate typing text from user names
    private func typingText(from names: [String]) -> String {
        if names.isEmpty {
            return "Someone is typing..."
        } else if names.count == 1 {
            return "\(names[0]) is typing..."
        } else if names.count == 2 {
            return "\(names[0]) and \(names[1]) are typing..."
        } else {
            return "\(names.count) people are typing..."
        }
    }
    
    // Show last message helper
    @ViewBuilder
    private func showLastMessage() -> some View {
        if let lastMessage = getLastMessage(from: room) {
            HStack(spacing: 4) {
                // Show sender name if it's not empty
                let senderName = lastMessage.user.fullName
                if !senderName.isEmpty {
                    Text("\(senderName): ")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Text(lastMessage.body)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        } else {
            Text("No messages yet")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .italic()
        }
    }
    
    private func timeString(from timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let formatter = DateFormatter()
        
        // Show relative time for recent messages
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        if timeInterval < 60 {
            // Less than a minute ago
            return "now"
        } else if timeInterval < 3600 {
            // Less than an hour ago - show minutes
            let minutes = Int(timeInterval / 60)
            return "\(minutes)m"
        } else if timeInterval < 86400 {
            // Less than a day ago - show hours
            let hours = Int(timeInterval / 3600)
            return "\(hours)h"
        } else if timeInterval < 604800 {
            // Less than a week ago - show day name
            formatter.dateFormat = "EEE"
            return formatter.string(from: date)
        } else {
            // Older - show date
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
}

// MARK: - Room List ViewModel
@MainActor
public class RoomListViewModel: ObservableObject {
    @Published var rooms: [Room] = []
    @Published var showNewChatModal: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    let client: XMPPClient
    let currentUserId: String
    private let apiBaseURL: URL
    private let appId: String
    private let conferenceDomain: String
    
    // Auto-load history queue
    private var messageLoaderQueue: MessageLoaderQueue?
    
    // Composing timeouts per room
    private var composingTimeouts: [String: Timer] = [:]
    private var notificationObservers: [NSObjectProtocol] = []
    
    // New initializer - token is now managed by UserStore
    public init(
        client: XMPPClient,
        currentUserId: String,
        appId: String? = nil,
        apiBaseURL: URL = URL(string: "https://api.chat.ethora.com/v1")!,
        conferenceDomain: String = "conference.xmpp.chat.ethora.com"
    ) {
        self.client = client
        self.currentUserId = currentUserId
        self.appId = appId ?? AppConfig.defaultAppId
        self.apiBaseURL = apiBaseURL
        self.conferenceDomain = conferenceDomain
        
        // Initialize message loader queue
        let queue = MessageLoaderQueue(client: client)
        queue.setRoomsProvider { [weak self] in
            self?.rooms ?? []
        }
        queue.setGlobalLoadingProvider { [weak self] in
            self?.isLoading ?? false
        }
        queue.setLoadingProvider { [weak self] in
            self?.isLoading ?? false
        }
        self.messageLoaderQueue = queue
        
        // Listen for room messages updates to continue loading if needed
        let roomMessagesUpdatedToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("RoomMessagesUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let roomJID = userInfo["roomJID"] as? String,
                  let messageCount = userInfo["messageCount"] as? Int else {
                return
            }
            self?.messageLoaderQueue?.onRoomMessagesUpdated(
                roomJID: roomJID,
                currentMessageCount: messageCount
            )
        }
        notificationObservers.append(roomMessagesUpdatedToken)
        
        // Start queue when client comes online
        let didConnectToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("XMPPClientDidConnect"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if let self = self, !self.rooms.isEmpty {
                self.messageLoaderQueue?.reset()
                self.messageLoaderQueue?.start()
                // After reconnect (or fresh connect after app relaunch) fetch
                // the latest slice of history for every known room, so any
                // messages that arrived while the app was offline show up
                // immediately — without the user having to open each chat.
                Task { @MainActor [weak self] in
                    await self?.refreshLatestForAllRooms()
                }
                //print("🔄 RoomListViewModel: Started auto-load history queue (client connected)")
            }
        }
        notificationObservers.append(didConnectToken)
        
        // Listen for room messages updates to update the room's messages array
        let roomMessagesRefreshToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("RoomMessagesUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let roomJID = userInfo["roomJID"] as? String,
                  let messageCount = userInfo["messageCount"] as? Int else {
                return
            }
            
            // Find the room and update its messages from cache
            if let roomIndex = self.rooms.firstIndex(where: { $0.jid == roomJID }) {
                // Load messages from cache (they were just saved by processIncomingMessage)
                if let cachedMessages = MessageCache.shared.loadMessages(forRoomJID: roomJID) {
                    // Update room's messages array
                    self.rooms[roomIndex].messages = cachedMessages
                    
                    // Notify MessageLoaderQueue about the update
                    self.messageLoaderQueue?.onRoomMessagesUpdated(
                        roomJID: roomJID,
                        currentMessageCount: cachedMessages.count
                    )
                    
                    // Trigger UI update
                    self.objectWillChange.send()
                    
                    //print("✅ RoomListViewModel: Updated room \(roomJID) with \(cachedMessages.count) messages from cache")
                }
            }
        }
        notificationObservers.append(roomMessagesRefreshToken)
        
        // Listen for composing (typing) indicator changes
        let composingChangedToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("XMPPComposingChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let roomJID = userInfo["roomJID"] as? String,
                  let composingList = userInfo["composingList"] as? [String],
                  let isComposing = userInfo["isComposing"] as? Bool else {
                return
            }
            
            // Find the room and update its composing state
            if let roomIndex = self.rooms.firstIndex(where: { $0.jid == roomJID || $0.jid.components(separatedBy: "/").first == roomJID }) {
                // Filter out current user from composing list
                let filteredComposingList = composingList.filter { userId in
                    let normalizedUserId = userId.lowercased().trimmingCharacters(in: .whitespaces)
                    let normalizedCurrentId = self.currentUserId.lowercased().trimmingCharacters(in: .whitespaces)
                    return normalizedUserId != normalizedCurrentId
                }
                
                let roomJIDKey = self.rooms[roomIndex].jid
                
                // Cancel existing timeout for this room
                self.composingTimeouts[roomJIDKey]?.invalidate()
                self.composingTimeouts.removeValue(forKey: roomJIDKey)
                
                if isComposing && !filteredComposingList.isEmpty {
                    // Update room's composing state
                    self.rooms[roomIndex].composing = true
                    self.rooms[roomIndex].composingList = filteredComposingList
                    
                    // Set timeout to clear composing state after 3 seconds
                    let timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                        Task { @MainActor in
                            guard let self = self,
                                  let roomIndex = self.rooms.firstIndex(where: { $0.jid == roomJIDKey }) else {
                                return
                            }
                            
                            // Clear composing state
                            self.rooms[roomIndex].composing = false
                            self.rooms[roomIndex].composingList = []
                            
                            // Update RoomStore
                            var updates = PartialRoomUpdate()
                            updates.composing = false
                            updates.composingList = []
                            RoomStore.shared.updateRoom(jid: roomJIDKey, updates: updates)
                            
                            // Trigger UI update
                            self.objectWillChange.send()
                        }
                    }
                    self.composingTimeouts[roomJIDKey] = timer
                } else {
                    // Clear composing state immediately
                    self.rooms[roomIndex].composing = false
                    self.rooms[roomIndex].composingList = []
                }
                
                // Update RoomStore
                var updates = PartialRoomUpdate()
                updates.composing = self.rooms[roomIndex].composing
                updates.composingList = self.rooms[roomIndex].composingList
                RoomStore.shared.updateRoom(jid: roomJIDKey, updates: updates)
                
                // Trigger UI update
                self.objectWillChange.send()
                
                //print("⌨️ RoomListViewModel: Updated composing state for room \(roomJID) - isComposing: \(isComposing), users: \(filteredComposingList)")
            }
        }
        notificationObservers.append(composingChangedToken)
    }
    
    deinit {
        // Never capture `self` in async work from `deinit`.
        let queue = messageLoaderQueue
        let timers = Array(composingTimeouts.values)
        let observers = notificationObservers
        Task { @MainActor in
            queue?.stop()
            timers.forEach { $0.invalidate() }
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }
    
    public func loadRooms() {
        // FORCE VISIBLE LOGGING
        errorMessage = nil

        // Stale-while-revalidate: first show the cached list of rooms from
        // `RoomStore` (+ cached messages via `MessageCache`) so the UI
        // doesn't sit on a ProgressView while REST is in flight. If the
        // cache is present, set `isLoading = false` immediately and run
        // REST in the background, seamlessly replacing the list with fresh
        // data. If REST fails (no network), the cache stays on screen.
        let cachedRooms = Array(RoomStore.shared.rooms.values)
        if !cachedRooms.isEmpty {
            self.rooms = cachedRooms.map { room in
                var r = room
                if let cachedMessages = MessageCache.shared.loadMessages(forRoomJID: r.jid) {
                    r.messages = cachedMessages
                }
                return r
            }
            self.isLoading = false
        } else {
            isLoading = true
        }

        // Check UserStore state before loading
        Task { @MainActor in
            let isAuth = UserStore.shared.isAuthenticated
            let hasToken = UserStore.shared.token != nil
            let userEmail = UserStore.shared.currentUser?.email ?? "nil"

            guard isAuth, hasToken else {
                let msg = "User not authenticated. Please login first."
                // Don't wipe the cached list — if the user got signed out
                // because of an expired token, we still show the last known
                // state. A full reset is the job of `LogoutManager`.
                if self.rooms.isEmpty {
                    self.errorMessage = msg
                }
                self.isLoading = false
                return
            }


            do {
                // RoomsAPI now uses UserStore automatically
                let loadedRooms = try await RoomsAPI.getRooms(
                    baseURL: apiBaseURL,
                    appId: appId,
                    conferenceDomain: conferenceDomain
                )

                // Load cached messages for each room
                var roomsWithCachedMessages: [Room] = []
                for var room in loadedRooms {
                    if let cachedMessages = MessageCache.shared.loadMessages(forRoomJID: room.jid) {
                        room.messages = cachedMessages
                        //print("📂 RoomListViewModel: Loaded \(cachedMessages.count) cached messages for room: \(room.jid)")
                    }
                    roomsWithCachedMessages.append(room)
                }

                self.rooms = roomsWithCachedMessages
                self.isLoading = false // Set to false BEFORE starting queue

                // Save the fresh list to `RoomStore` so the next app launch
                // starts with an up-to-date cache. Remove JIDs from the
                // store that are no longer in the fresh list so the cache
                // doesn't keep growing after rooms get deleted.
                let freshJIDs = Set(roomsWithCachedMessages.map { $0.jid })
                for existing in RoomStore.shared.rooms.keys where !freshJIDs.contains(existing) {
                    RoomStore.shared.deleteRoom(jid: existing)
                }
                for room in roomsWithCachedMessages {
                    RoomStore.shared.addRoom(room)
                }
                
                // After loading rooms, send presence to each room
                // This is needed so the user can receive history for each room
                if !loadedRooms.isEmpty {
                    let roomJIDs = loadedRooms.compactMap { $0.jid }
                    _ = await client.joinRoomsAndWait(roomJIDs: roomJIDs, timeout: 3.5)

                    // Start auto-loading history for all rooms when XMPP is idle
                    if client.checkOnline() {
                        //print("🔄 RoomListViewModel: Client is online, starting auto-load queue")
                        //print("   Rooms count: \(self.rooms.count)")
                        //print("   Rooms with < 20 messages: \(self.rooms.filter { $0.messages.count < 20 }.count)")
                        messageLoaderQueue?.reset() // Reset to process all rooms
                        messageLoaderQueue?.start()
                        //print("✅ RoomListViewModel: Started auto-load history queue")

                        // Pull the latest slice of history for every room so
                        // new incoming messages (that arrived while the app
                        // was closed) appear in the list and unread badges
                        // immediately, without waiting for the user to open
                        // each chat one by one.
                        await refreshLatestForAllRooms()
                    } else {
                        //print("⚠️ RoomListViewModel: Client is not online, cannot start auto-load queue")
                    }
                }

                // RN: pushSubscriptionService.subscribeToRooms after rooms + presence (MUC push / MUCSub).
                Task {
                    await PushNotificationManager.shared.refreshRoomPushSubscriptions()
                }
            } catch {
                let errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                // If the cache is already on screen, don't overlay it with
                // an error state; offline mode: the user sees last rooms
                // and messages without a red banner on top of working UI.
                if self.rooms.isEmpty {
                    self.errorMessage = "Failed to load rooms: \(errorMsg)"
                }
                self.isLoading = false
                print("❌ RoomListViewModel.loadRooms error: \(errorMsg) (cache \(self.rooms.isEmpty ? "empty" : "served"))")
            }
        }
    }

    /// Fetches the last slice of MAM history for every known room so any
    /// messages that arrived while the app was offline land in the cache and
    /// unread badges right after connect. Results are handled through the
    /// normal stanza pipeline (`onMessageHistory` → `processIncomingMessage`
    /// → `RoomMessagesUpdated` notification), and the `id`-based
    /// deduplication downstream takes care of already-cached messages.
    private func refreshLatestForAllRooms() async {
        guard client.checkOnline() else { return }
        let jids = rooms.compactMap { $0.jid }
        guard !jids.isEmpty else { return }

        for jid in jids {
            client.operations.sendGetHistory(chatJID: jid, max: 10, before: nil)
            // Small pause so we don't slam ejabberd's MAM with parallel
            // get-histories on login / reconnect.
            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        // Give MAM results a moment to flow through the stanza pipeline and
        // land in MessageCache / RoomStore, then recompute unread badges
        // from scratch so rooms that got new messages while the app was
        // offline show the correct count. Real-time bumping in
        // `XMPPClient.onMessageReceived` takes care of further increments.
        try? await Task.sleep(nanoseconds: 1_200_000_000) // 1.2s
        recountUnreadFromCache()
    }

    /// Recomputes `Room.unreadMessages` for every room by counting messages
    /// in the cache newer than `lastViewedTimestamp`, excluding the active
    /// room (user is looking at it) and the user's own messages. Mirrors the
    /// React Native `unreadMiddleware` approach but runs on demand instead
    /// of on every Redux action.
    private func recountUnreadFromCache() {
        let activeJID = RoomStore.shared.activeRoomJID
        let myLocal = UserStore.shared.currentUser?.xmppUsername?
            .components(separatedBy: "@").first ?? ""

        for (jid, room) in RoomStore.shared.rooms {
            if jid == activeJID {
                RoomStore.shared.updateUnreadCount(roomJID: jid, count: 0)
                continue
            }
            let cached = MessageCache.shared.loadMessages(forRoomJID: jid) ?? room.messages
            let lastViewed = room.lastViewedTimestamp ?? 0
            let unread = cached.reduce(0) { acc, msg in
                guard msg.isDeleted != true else { return acc }
                guard (msg.timestamp ?? 0) > lastViewed else { return acc }
                let senderLocal = msg.user.xmppUsername?
                    .components(separatedBy: "@").first ?? ""
                guard senderLocal != myLocal else { return acc }
                return acc + 1
            }
            if unread != room.unreadMessages {
                RoomStore.shared.updateUnreadCount(roomJID: jid, count: unread)
            }
        }
    }
    
    public func createRoom(title: String, description: String, members: [User] = []) async throws {
        guard let token = UserStore.shared.token else {
            throw NSError(domain: "RoomListViewModel", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Create room via API first
            let memberIds = members.compactMap { $0.id }
            let apiRoom = try await RoomsAPI.postRoom(
                title: title,
                type: RoomType.public,
                description: description,
                picture: nil,
                members: memberIds.isEmpty ? nil : memberIds,
                baseURL: apiBaseURL,
                appId: appId
            )
            
            // Create room via XMPP
            // Note: createRoom is async, so we await it
            let roomJID = try await client.operations.createRoom(
                title: title,
                description: description,
                conferenceDomain: conferenceDomain
            )
            
            // Invite members if provided
            for member in members {
                if let memberJID = member.xmppUsername {
                    try await client.operations.inviteRoomRequest(
                        to: memberJID,
                        roomJid: roomJID,
                        chatDomain: conferenceDomain
                    )
                }
            }
            
            // Reload rooms to include the new one
            loadRooms()
            
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = "Failed to create room: \(error.localizedDescription)"
            throw error
        }
    }
    
    public func createPrivateRoom(with user: User) async throws {
        guard let token = UserStore.shared.token else {
            throw NSError(domain: "RoomListViewModel", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        guard let userJID = user.xmppUsername else {
            throw NSError(domain: "RoomListViewModel", code: 400, userInfo: [NSLocalizedDescriptionKey: "User JID not available"])
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Create private room via API
            let apiRoom = try await RoomsAPI.postPrivateRoom(
                username: userJID,
                baseURL: apiBaseURL,
                appId: appId
            )
            
            // Create private room via XMPP
            let roomJID = try await client.operations.createPrivateRoom(
                title: user.fullName,
                description: "",
                to: userJID,
                conferenceDomain: conferenceDomain
            )
            
            // Reload rooms to include the new one
            loadRooms()
            
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = "Failed to create private room: \(error.localizedDescription)"
            throw error
        }
    }
    
    // Get available users from existing rooms (for now)
    // In a real app, you'd fetch this from an API
    public func getAvailableUsers() -> [User] {
        var users: Set<String> = []
        var userMap: [String: User] = [:]
        
        // Collect unique users from all rooms
        for room in rooms {
            for message in room.messages {
                if !users.contains(message.user.id) {
                    users.insert(message.user.id)
                    userMap[message.user.id] = message.user
                }
            }
        }
        
        // Exclude current user
        return Array(userMap.values).filter { $0.id != currentUserId }
    }

    /// If a push stored a room JID (see `PendingNotificationJidStore`) and that room is loaded, clears storage and returns the bare JID to navigate to.
    public func pendingPushRoomJIDToOpen() -> String? {
        guard let bare = PendingNotificationJidStore.peekPendingBareJid() else { return nil }
        let hasRoom = rooms.contains { room in
            let rb = room.jid.components(separatedBy: "/").first ?? room.jid
            return rb.caseInsensitiveCompare(bare) == .orderedSame
        }
        guard hasRoom else { return nil }
        PendingNotificationJidStore.clearPendingJid()
        return bare
    }
}

extension RoomListViewModel {
    /// Preferred initializer when using `ChatConfig` (e.g. `ChatWrapperView`).
    public convenience init(client: XMPPClient, currentUserId: String, config: ChatConfig) {
        let baseURL = URL(string: config.baseUrl ?? AppConfig.defaultBaseURL.absoluteString) ?? AppConfig.defaultBaseURL
        let resolvedAppId = config.appId ?? AppConfig.defaultAppId
        let conference = config.xmppSettings?.conference
            ?? AppConfig.defaultXMPPSettings.conference
            ?? "conference.xmpp.chat.ethora.com"
        self.init(
            client: client,
            currentUserId: currentUserId,
            appId: resolvedAppId,
            apiBaseURL: baseURL,
            conferenceDomain: conference
        )
    }
}


