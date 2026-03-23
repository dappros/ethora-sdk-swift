//
//  ChatRoomView.swift
//  XMPPChatUI
//
//  SwiftUI Chat Room component
//

import SwiftUI
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import WebKit
import AVKit
import PhotosUI
import UniformTypeIdentifiers
import UIKit
#endif
import XMPPChatCore
import AVFoundation

// Preference key for scroll metrics tracking
struct ScrollMetrics: Equatable {
    let scrollTop: CGFloat
    let scrollHeight: CGFloat
    let clientHeight: CGFloat
}

struct ScrollMetricsKey: PreferenceKey {
    static var defaultValue: ScrollMetrics = ScrollMetrics(scrollTop: 0, scrollHeight: 0, clientHeight: 0)
    static func reduce(value: inout ScrollMetrics, nextValue: () -> ScrollMetrics) {
        let next = nextValue()
        // We receive two metric sources:
        // - inner content: scrollTop + scrollHeight (clientHeight = 0)
        // - outer viewport: clientHeight only
        // Keep each field from the source that owns it.
        value = ScrollMetrics(
            scrollTop: next.scrollHeight > 0 ? next.scrollTop : value.scrollTop,
            scrollHeight: next.scrollHeight > 0 ? next.scrollHeight : value.scrollHeight,
            clientHeight: next.clientHeight > 0 ? next.clientHeight : value.clientHeight
        )
    }
}

struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

public struct ChatRoomView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var viewModel: ChatRoomViewModel
    @State internal var messageText: String = ""
    @State internal var scrollOffset: CGFloat = 0
    @State internal var showScrollButton: Bool = false
    @State internal var newMessagesCount: Int = 0
    @State internal var lastMessageCount: Int = 0
    @State internal var scrollHeight: CGFloat = 0
    @State internal var scrollTop: CGFloat = 0
    @State internal var clientHeight: CGFloat = 0
    @State internal var contentHeight: CGFloat = 0
    @State internal var isUserScrolledUp: Bool = false
    @State internal var atBottom: Bool = true
    @State internal var scrollProxy: ScrollViewProxy?
    @FocusState internal var isInputFocused: Bool
    @State internal var showConnectionStatus: Bool = true
    @State internal var dragOffset: CGFloat = 0
    @State internal var showSearch: Bool = false
    @State internal var showRoomInfo: Bool = false
    @State internal var selectedMessageForMenu: Message? = nil
    @State internal var showThread: Bool = false
    @State internal var selectedMessageForThread: Message? = nil
    @State internal var showReportModal: Bool = false
    @State internal var messageToReport: Message? = nil
    @State internal var showFullScreenImage: Bool = false
    @State internal var showFullScreenVideo: Bool = false
    @State internal var showFullScreenPDF: Bool = false
    @State internal var selectedMediaMessage: Message? = nil
    @State internal var needsInitialScroll: Bool = true
    @State internal var allowLoadMore: Bool = false
    @State internal var isHistoryPaginationInProgress: Bool = false
    @ObservedObject internal var connectionManager: ConnectionManager
    @State internal var lastHistoryCheckAt: Date?
    
    internal let historyCheckThrottleInterval: TimeInterval = 0.15
    
    public init(viewModel: ChatRoomViewModel) {
        self.viewModel = viewModel
        self._connectionManager = ObservedObject(wrappedValue: ConnectionManager.shared)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if showConnectionStatus {
                ConnectionStatusView(connectionManager: connectionManager)
            }
            
            ChatHeaderView(
                room: viewModel.room,
                isTyping: viewModel.isTyping,
                composingUsers: viewModel.composingUsers,
                messages: viewModel.messages,
                currentUserId: viewModel.currentUserId,
                currentUserXmppUsername: viewModel.currentUserXmppUsername,
                config: viewModel.config,
                onBack: { presentationMode.wrappedValue.dismiss() },
                onInfo: { showRoomInfo = true }
            )
            
            OffClinicHoursBanner()
            
            ZStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        MessagesListView(
                            viewModel: viewModel,
                            messageText: $messageText,
                            selectedMessageForThread: $selectedMessageForThread,
                            showThread: $showThread,
                            selectedMediaMessage: $selectedMediaMessage,
                            showFullScreenImage: $showFullScreenImage,
                            showFullScreenVideo: $showFullScreenVideo,
                            showFullScreenPDF: $showFullScreenPDF,
                            messageToReport: $messageToReport,
                            showReportModal: $showReportModal,
                            proxy: proxy
                        )
                        .padding()
                        .background(
                            GeometryReader { geometry in
                                Color.clear
                                    .preference(key: ContentHeightKey.self, value: geometry.size.height)
                                    .preference(key: ScrollMetricsKey.self, value: ScrollMetrics(
                                        scrollTop: max(0, -geometry.frame(in: .named("messageScroll")).minY),
                                        scrollHeight: geometry.size.height,
                                        clientHeight: 0
                                    ))
                            }
                        )
                    }
                    #if os(iOS)
                    .scrollDismissesKeyboardIfAvailable()
                    .simultaneousGesture(DragGesture().onChanged { _ in dismissKeyboard() })
                    .simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })
                    #endif
                    .coordinateSpace(name: "messageScroll")
                    .chatRoomModals(
                        showThread: $showThread,
                        selectedMessageForThread: $selectedMessageForThread,
                        showReportModal: $showReportModal,
                        messageToReport: $messageToReport,
                        showRoomInfo: $showRoomInfo,
                        showFullScreenImage: $showFullScreenImage,
                        showFullScreenVideo: $showFullScreenVideo,
                        showFullScreenPDF: $showFullScreenPDF,
                        selectedMediaMessage: $selectedMediaMessage,
                        viewModel: viewModel
                    )
                    .background(
                        GeometryReader { outerGeometry in
                            Color.clear
                                .preference(key: ScrollMetricsKey.self, value: ScrollMetrics(
                                    scrollTop: 0, scrollHeight: 0, clientHeight: outerGeometry.size.height
                                ))
                        }
                    )
                    .onPreferenceChange(ScrollMetricsKey.self) { metrics in
                        handleScroll(metrics: metrics, proxy: proxy)
                    }
                    .onPreferenceChange(ContentHeightKey.self) { height in
                        contentHeight = height
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MessagesLoaded"))) { notification in
                        handleMessagesLoaded(notification, proxy: proxy)
                    }
                    .onChange(of: viewModel.messages.count) { newCount in
                        handleMessageCountChange(newCount, proxy: proxy)
                    }
                    .onAppear {
                        needsInitialScroll = true
                        allowLoadMore = false
                        scrollProxy = proxy
                        viewModel.onViewAppeared()
                        
                        // If messages are already cached and count does not change,
                        // force initial positioning to newest messages.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            guard needsInitialScroll, !viewModel.messages.isEmpty else { return }
                            scrollToBottom(proxy: proxy, animated: false)
                            // Consume first-load flag in fallback path as well.
                            _ = viewModel.shouldScrollToBottom()
                            needsInitialScroll = false
                            allowLoadMore = true
                            lastMessageCount = viewModel.messages.count
                        }
                    }
                }
                
                scrollOverlay()
            }
            
            chatInputSection()
        }
    }
}

// Helper views and sections to reduce body size
extension ChatRoomView {
    @ViewBuilder
    internal func scrollOverlay() -> some View {
        Group {
            if showScrollButton {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            if let proxy = scrollProxy { scrollToBottom(proxy: proxy) }
                        }) {
                            ScrollToBottomButton(newMessagesCount: newMessagesCount)
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
            
            if viewModel.isTyping && !viewModel.composingUsers.isEmpty {
                VStack {
                    Spacer()
                    TypingIndicatorView(users: viewModel.composingUsers)
                        .padding(.bottom, 8)
                }
            }
        }
    }
    
    @ViewBuilder
    internal func chatInputSection() -> some View {
        ChatInputView(
            text: $messageText,
            onSend: {
                if viewModel.isEditing, let editId = viewModel.editMessageId {
                    viewModel.editMessage(editId, newText: messageText)
                } else {
                    viewModel.sendMessage(messageText)
                }
                messageText = ""
            },
            onSendMedia: { data, type in
                viewModel.sendMedia(data: data, type: type)
            },
            isEditing: viewModel.isEditing,
            editText: viewModel.editText,
            onCancelEdit: {
                viewModel.isEditing = false
                viewModel.editText = nil
                viewModel.editMessageId = nil
                messageText = ""
            }
        )
    }
}

struct ScrollToBottomButton: View {
    let newMessagesCount: Int
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 44, height: 44)
                .shadow(radius: 4)
            Image(systemName: "chevron.down")
                .foregroundColor(.blue)
                .font(.system(size: 18, weight: .bold))
            if newMessagesCount > 0 {
                Text("\(newMessagesCount)")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.red)
                    .clipShape(Circle())
                    .offset(x: 15, y: -15)
            }
        }
    }
}

#if os(iOS)
extension View {
    func scrollDismissesKeyboardIfAvailable() -> some View {
        if #available(iOS 16.0, *) {
            return self.scrollDismissesKeyboard(.interactively)
        } else {
            return self
        }
    }
}
#endif
