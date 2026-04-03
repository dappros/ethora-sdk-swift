//
//  ChatWrapperView.swift
//  XMPPChatUI
//
//  High‑level SwiftUI wrapper that mirrors the web ChatWrapper.tsx behavior:
//  - shows loaders while initializing
//  - surfaces connection status banner
//  - renders room list + chat rooms once initialized
//  - handles simple rooms‑retry and "no rooms" helper states
//

import SwiftUI
import Combine
import XMPPChatCore

@MainActor
public struct ChatWrapperView: View {
    @StateObject private var viewModel: ChatWrapperViewModel
    
    private let config: ChatConfig
    private let onUnreadCountChanged: ((Int) -> Void)?
    
    public init(
        config: ChatConfig? = nil,
        initialRoomJID: String? = nil,
        wasAutoSelected: Bool = false,
        onUnreadCountChanged: ((Int) -> Void)? = nil
    ) {
        // Access ConfigStore on main actor if config not provided
        let resolvedConfig: ChatConfig
        if let providedConfig = config {
            resolvedConfig = providedConfig
        } else {
            resolvedConfig = ConfigStore.shared.config
        }
        
        self._viewModel = StateObject(
            wrappedValue: ChatWrapperViewModel(
                config: resolvedConfig,
                initialRoomJID: initialRoomJID,
                wasAutoSelected: wasAutoSelected
            )
        )
        self.config = resolvedConfig
        self.onUnreadCountChanged = onUnreadCountChanged
    }
    
    public var body: some View {
        Group {
            // 1. Missing user / XMPP credentials – let hosting app present its own login UI.
            if viewModel.showModal {
                VStack(spacing: 12) {
                    Text("User is not authenticated for chat.")
                        .font(.headline)
                    Text("Please ensure the user is logged in and has XMPP credentials configured.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            // 2. Rooms retry: "no rooms" state (equivalent to web isRetrying === 'norooms').
            else if config.enableRoomsRetry?.enabled == true,
                    viewModel.roomsRetryState == .noRooms {
                VStack(spacing: 12) {
                    Text(config.enableRoomsRetry?.helperText
                         ?? "We couldn't create or load any chat room.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            // 3. Rooms retry: retrying state (equivalent to web isRetrying === true).
            else if config.enableRoomsRetry?.enabled == true,
                    viewModel.roomsRetryState == .retrying {
                VStack(spacing: 12) {
                    ProgressView()
                    if let loading = viewModel.loadingText {
                        Text(loading)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Loading rooms...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            // 4. Wrapper not yet initialized – general loader.
            else if !viewModel.inited {
                VStack(spacing: 12) {
                    ProgressView()
                    if let loading = viewModel.loadingText {
                        Text(loading)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Preparing chat...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            // 5. Initialized and client available – render main chat UI.
            else if let client = viewModel.client {
                VStack(spacing: 0) {
                    // Connection banner at top (equivalent to web ConnectionBanner).
                    ConnectionStatusView(connectionManager: ConnectionManager.shared)
                    
                    // Main content: room list + chat rooms, reusing existing RoomListView.
                    RoomListView(
                        viewModel: RoomListViewModel(
                            client: client,
                            currentUserId: viewModel.currentUserId,
                            config: config
                        )
                    )
                }
            } else {
                // Safety fallback – should not normally happen.
                VStack(spacing: 12) {
                    Text("Chat client is not available.")
                        .font(.headline)
                    Text("Please try again later.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
        .onReceive(RoomStore.shared.$rooms) { rooms in
            let count = rooms.values.reduce(0) { $0 + $1.unreadMessages }
            onUnreadCountChanged?(count)
        }
    }
}
