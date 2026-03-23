import SwiftUI
import XMPPChatCore

extension View {
    func chatRoomModals(
        showThread: Binding<Bool>,
        selectedMessageForThread: Binding<Message?>,
        showReportModal: Binding<Bool>,
        messageToReport: Binding<Message?>,
        showRoomInfo: Binding<Bool>,
        showFullScreenImage: Binding<Bool>,
        showFullScreenVideo: Binding<Bool>,
        showFullScreenPDF: Binding<Bool>,
        selectedMediaMessage: Binding<Message?>,
        viewModel: ChatRoomViewModel
    ) -> some View {
        modifier(
            ChatRoomModalsModifier(
                showThread: showThread,
                selectedMessageForThread: selectedMessageForThread,
                showReportModal: showReportModal,
                messageToReport: messageToReport,
                showRoomInfo: showRoomInfo,
                showFullScreenImage: showFullScreenImage,
                showFullScreenVideo: showFullScreenVideo,
                showFullScreenPDF: showFullScreenPDF,
                selectedMediaMessage: selectedMediaMessage,
                viewModel: viewModel
            )
        )
    }
}

private struct ChatRoomModalsModifier: ViewModifier {
    @Binding var showThread: Bool
    @Binding var selectedMessageForThread: Message?
    @Binding var showReportModal: Bool
    @Binding var messageToReport: Message?
    @Binding var showRoomInfo: Bool
    @Binding var showFullScreenImage: Bool
    @Binding var showFullScreenVideo: Bool
    @Binding var showFullScreenPDF: Bool
    @Binding var selectedMediaMessage: Message?
    @ObservedObject var viewModel: ChatRoomViewModel
    @State private var imageURLResolveAttempts: Int = 0
    
    private func resolvedURL(_ raw: String?) -> URL? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        if let direct = URL(string: raw), direct.scheme != nil {
            return direct
        }
        if let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
           let encodedURL = URL(string: encoded),
           encodedURL.scheme != nil {
            return encodedURL
        }
        return nil
    }
    
    private func freshestMediaMessage() -> Message? {
        guard let selected = selectedMediaMessage else { return nil }
        if let refreshed = viewModel.messages.first(where: {
            $0.id == selected.id ||
            ($0.xmppId != nil && $0.xmppId == selected.id) ||
            (selected.xmppId != nil && $0.id == selected.xmppId) ||
            ($0.xmppId != nil && selected.xmppId != nil && $0.xmppId == selected.xmppId)
        }) {
            return refreshed
        }
        return selected
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showThread) {
                if let message = selectedMessageForThread,
                   let currentUser = UserStore.shared.currentUser {
                    ThreadView(
                        activeMessage: message,
                        currentUser: currentUser,
                        onClose: {
                            showThread = false
                            selectedMessageForThread = nil
                        },
                        onSendMessage: { text, alsoSendToMain in
                            viewModel.sendReply(messageId: message.id, text: text, alsoSendToMain: alsoSendToMain)
                        },
                        onSendMedia: { data, type in
                            viewModel.sendMedia(data: data, type: type)
                        }
                    )
                }
            }
            .sheet(isPresented: $showReportModal) {
                if let message = messageToReport {
                    ReportModal(
                        type: .message,
                        onReport: { reason, additionalInfo in
                            Task {
                                do {
                                    let chatName = viewModel.room.jid.components(separatedBy: "@").first ?? viewModel.room.jid
                                    _ = try await RoomsAPI.postReportMessage(
                                        chatName: chatName,
                                        messageId: message.id,
                                        category: reason,
                                        text: additionalInfo.isEmpty ? nil : additionalInfo
                                    )
                                } catch {}
                            }
                        },
                        onClose: {
                            showReportModal = false
                            messageToReport = nil
                        }
                    )
                }
            }
            .sheet(isPresented: $showRoomInfo) {
                RoomInfoModal(
                    room: viewModel.room,
                    members: viewModel.room.members ?? [],
                    onClose: { showRoomInfo = false },
                    onEdit: nil, onLeave: nil, onDelete: nil
                )
            }
            .sheet(isPresented: $showFullScreenImage) {
                if let message = freshestMediaMessage(),
                   let url = resolvedURL(message.location) ?? resolvedURL(message.locationPreview) {
                    FullScreenImageView(
                        imageURL: url,
                        onClose: {
                            showFullScreenImage = false
                            selectedMediaMessage = nil
                            imageURLResolveAttempts = 0
                        }
                    )
                } else {
                    VStack(spacing: 12) {
                        if imageURLResolveAttempts < 3 {
                            ProgressView()
                            Text("Loading image...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Unable to open image")
                                .font(.headline)
                            Text("Invalid or missing image URL")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Button(imageURLResolveAttempts < 3 ? "Cancel" : "Close") {
                            showFullScreenImage = false
                            selectedMediaMessage = nil
                            imageURLResolveAttempts = 0
                        }
                        .padding(.top, 6)
                    }
                    .padding()
                    .onAppear {
                        guard imageURLResolveAttempts < 3 else { return }
                        let nextAttempt = imageURLResolveAttempts + 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            // Pull freshest copy from room messages; URL often appears shortly after tap.
                            if let refreshed = freshestMediaMessage() {
                                selectedMediaMessage = refreshed
                            }
                            imageURLResolveAttempts = nextAttempt
                        }
                    }
                }
            }
            .sheet(isPresented: $showFullScreenVideo) {
                if let message = selectedMediaMessage, let urlString = message.location, let url = URL(string: urlString) {
                    #if os(iOS)
                    FullScreenVideoView(videoURL: url, onClose: {
                        showFullScreenVideo = false
                        selectedMediaMessage = nil
                    })
                    #else
                    Text("Video playback is available on iOS")
                    #endif
                }
            }
            .sheet(isPresented: $showFullScreenPDF) {
                if let message = selectedMediaMessage, let urlString = message.location, let url = URL(string: urlString) {
                    FullScreenPDFView(pdfURL: url, fileName: message.fileName ?? message.originalName ?? "Document.pdf", onClose: {
                        showFullScreenPDF = false
                        selectedMediaMessage = nil
                    })
                }
            }
    }
}
