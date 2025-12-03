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
            currentUserId: currentUserId
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
    @State private var searchText: String = ""
    
    public init(viewModel: RoomListViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        NavigationView {
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
                            RoomListItemView(room: room)
                        }
                    }
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
                NewChatModalView(viewModel: viewModel)
            }
            .onAppear {
                // FORCE CALL loadRooms when view appears
                NSLog("🔥🔥🔥 ROOMLISTVIEW.ONAPPEAR CALLED 🔥🔥🔥")
                print("🔥🔥🔥 ROOMLISTVIEW.ONAPPEAR CALLED 🔥🔥🔥")
                print("📋 RoomListView.onAppear: View appeared")
                print("   ViewModel has \(viewModel.rooms.count) rooms")
                print("   isLoading: \(viewModel.isLoading)")
                
                // Call loadRooms if not already loading
                if !viewModel.isLoading && viewModel.rooms.isEmpty {
                    NSLog("🚀 Calling viewModel.loadRooms() from onAppear")
                    print("🚀 Calling viewModel.loadRooms() from onAppear")
                    viewModel.loadRooms()
                }
            }
        }
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

// MARK: - Room List Item
struct RoomListItemView: View {
    let room: Room
    
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
                    // Show last message from messages array if available, otherwise use lastMessage property
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
    
    // New initializer - token is now managed by UserStore
    public init(
        client: XMPPClient,
        currentUserId: String,
        appId: String? = nil,
        apiBaseURL: URL = URL(string: "https://api.ethoradev.com/v1")!,
        conferenceDomain: String = "conference.xmpp.ethoradev.com"
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
        NotificationCenter.default.addObserver(
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
        
        // Start queue when client comes online
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("XMPPClientDidConnect"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if let self = self, !self.rooms.isEmpty {
                self.messageLoaderQueue?.reset()
                self.messageLoaderQueue?.start()
                print("🔄 RoomListViewModel: Started auto-load history queue (client connected)")
            }
        }
        
        // Listen for room messages updates to update the room's messages array
        NotificationCenter.default.addObserver(
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
                    
                    print("✅ RoomListViewModel: Updated room \(roomJID) with \(cachedMessages.count) messages from cache")
                }
            }
        }
    }
    
    deinit {
        Task { @MainActor in
            messageLoaderQueue?.stop()
        }
        NotificationCenter.default.removeObserver(self)
    }
    
    public func loadRooms() {
        // FORCE VISIBLE LOGGING
        NSLog("🔥🔥🔥 ROOMLISTVIEWMODEL.LOADROOMS CALLED 🔥🔥🔥")
        print("🔥🔥🔥 ROOMLISTVIEWMODEL.LOADROOMS CALLED 🔥🔥🔥")
        
        isLoading = true
        errorMessage = nil
        NSLog("➡️ RoomListViewModel.loadRooms: Starting... baseURL=%@", apiBaseURL.absoluteString)
        print("➡️ RoomListViewModel.loadRooms: Starting... baseURL=\(apiBaseURL)")
        
        // Check UserStore state before loading
        Task { @MainActor in
            let isAuth = UserStore.shared.isAuthenticated
            let hasToken = UserStore.shared.token != nil
            let userEmail = UserStore.shared.currentUser?.email ?? "nil"
            
            NSLog("🔍 RoomListViewModel.loadRooms: UserStore state:")
            NSLog("   isAuthenticated: %@", isAuth ? "true" : "false")
            NSLog("   hasToken: %@", hasToken ? "true" : "false")
            NSLog("   userEmail: %@", userEmail)
            print("🔍 RoomListViewModel.loadRooms: UserStore state:")
            print("   isAuthenticated: \(isAuth)")
            print("   hasToken: \(hasToken)")
            print("   userEmail: \(userEmail)")
            
            guard isAuth, hasToken else {
                let msg = "User not authenticated. Please login first."
                self.errorMessage = msg
                self.isLoading = false
                NSLog("❌ RoomListViewModel.loadRooms: %@", msg)
                print("❌ RoomListViewModel.loadRooms: \(msg)")
                return
            }
            
            NSLog("✅ User authenticated, calling RoomsAPI.getRooms()")
            print("✅ User authenticated, calling RoomsAPI.getRooms()")
            
            do {
                // RoomsAPI now uses UserStore automatically
                let loadedRooms = try await RoomsAPI.getRooms(
                    baseURL: apiBaseURL,
                    appId: appId,
                    conferenceDomain: conferenceDomain
                )
                NSLog("✅ RoomListViewModel.loadRooms: Success! Loaded %d rooms", loadedRooms.count)
                print("✅ RoomListViewModel.loadRooms: Success! Loaded \(loadedRooms.count) rooms")
                
                // Load cached messages for each room
                var roomsWithCachedMessages: [Room] = []
                for var room in loadedRooms {
                    if let cachedMessages = MessageCache.shared.loadMessages(forRoomJID: room.jid) {
                        room.messages = cachedMessages
                        print("📂 RoomListViewModel: Loaded \(cachedMessages.count) cached messages for room: \(room.jid)")
                    }
                    roomsWithCachedMessages.append(room)
                }
                
                self.rooms = roomsWithCachedMessages
                self.isLoading = false // Set to false BEFORE starting queue
                
                // After loading rooms, send presence to each room
                // This is needed so the user can receive history for each room
                if !loadedRooms.isEmpty {
                    let roomJIDs = loadedRooms.compactMap { $0.jid }
                    await client.sendPresenceToAllRooms(roomJIDs: roomJIDs)
                    
                    // Start auto-loading history for all rooms when XMPP is idle
                    if client.checkOnline() {
                        print("🔄 RoomListViewModel: Client is online, starting auto-load queue")
                        print("   Rooms count: \(self.rooms.count)")
                        print("   Rooms with < 20 messages: \(self.rooms.filter { $0.messages.count < 20 }.count)")
                        messageLoaderQueue?.reset() // Reset to process all rooms
                        messageLoaderQueue?.start()
                        print("✅ RoomListViewModel: Started auto-load history queue")
                    } else {
                        print("⚠️ RoomListViewModel: Client is not online, cannot start auto-load queue")
                    }
                }
            } catch {
                let errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.errorMessage = "Failed to load rooms: \(errorMsg)"
                self.isLoading = false
                NSLog("❌ RoomListViewModel.loadRooms error: %@", errorMsg)
                NSLog("   Full error: %@", error.localizedDescription)
                print("❌ RoomListViewModel.loadRooms error: \(errorMsg)")
                print("   Full error: \(error)")
            }
        }
    }
    
    public func createRoom(title: String, description: String) {
        // Create new room
    }
}

// MARK: - New Chat Modal
struct NewChatModalView: View {
    @ObservedObject var viewModel: RoomListViewModel
    @Environment(\.dismiss) var dismiss
    @State private var title: String = ""
    @State private var description: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("Room Details") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description)
                }
            }
            .navigationTitle("New Chat")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        viewModel.createRoom(title: title, description: description)
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}

