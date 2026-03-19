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
                if let message = selectedMediaMessage, let urlString = message.location, let url = URL(string: urlString) {
                    FullScreenImageView(imageURL: url, onClose: {
                        showFullScreenImage = false
                        selectedMediaMessage = nil
                    })
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
