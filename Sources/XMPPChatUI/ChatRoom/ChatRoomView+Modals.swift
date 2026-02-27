//
//  ChatRoomView+Modals.swift
//  XMPPChatUI
//

import SwiftUI
import XMPPChatCore

extension View {
    func chatRoomModals(view: ChatRoomView) -> some View {
        self.modifier(ChatRoomModalsModifier(view: view))
    }
}

struct ChatRoomModalsModifier: ViewModifier {
    @ObservedObject var view: ChatRoomView
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $view.showThread) {
                if let message = view.selectedMessageForThread,
                   let currentUser = UserStore.shared.currentUser {
                    ThreadView(
                        activeMessage: message,
                        currentUser: currentUser,
                        onClose: {
                            view.showThread = false
                            view.selectedMessageForThread = nil
                        },
                        onSendMessage: { text, alsoSendToMain in
                            view.viewModel.sendReply(messageId: message.id, text: text, alsoSendToMain: alsoSendToMain)
                        },
                        onSendMedia: { data, type in
                            view.viewModel.sendMedia(data: data, type: type)
                        }
                    )
                }
            }
            .sheet(isPresented: $view.showReportModal) {
                if let message = view.messageToReport {
                    ReportModal(
                        type: .message,
                        onReport: { reason, additionalInfo in
                            view.handleReport(message: message, reason: reason, additionalInfo: additionalInfo)
                        },
                        onClose: {
                            view.showReportModal = false
                            view.messageToReport = nil
                        }
                    )
                }
            }
            .sheet(isPresented: $view.showRoomInfo) {
                RoomInfoModal(
                    room: view.viewModel.room,
                    members: view.viewModel.room.members ?? [],
                    onClose: { view.showRoomInfo = false },
                    onEdit: nil, onLeave: nil, onDelete: nil
                )
            }
            .fullScreenCover(isPresented: $view.showFullScreenImage) {
                if let message = view.selectedMediaMessage, let urlString = message.location, let url = URL(string: urlString) {
                    FullScreenImageView(imageURL: url, onClose: {
                        view.showFullScreenImage = false
                        view.selectedMediaMessage = nil
                    })
                }
            }
            .fullScreenCover(isPresented: $view.showFullScreenVideo) {
                if let message = view.selectedMediaMessage, let urlString = message.location, let url = URL(string: urlString) {
                    FullScreenVideoView(videoURL: url, onClose: {
                        view.showFullScreenVideo = false
                        view.selectedMediaMessage = nil
                    })
                }
            }
            .sheet(isPresented: $view.showFullScreenPDF) {
                if let message = view.selectedMediaMessage, let urlString = message.location, let url = URL(string: urlString) {
                    FullScreenPDFView(pdfURL: url, fileName: message.fileName ?? message.originalName ?? "Document.pdf", onClose: {
                        view.showFullScreenPDF = false
                        view.selectedMediaMessage = nil
                    })
                }
            }
    }
}

extension ChatRoomView {
    func handleReport(message: Message, reason: String, additionalInfo: String) {
        Task {
            do {
                let chatName = viewModel.room.jid.components(separatedBy: "@").first ?? viewModel.room.jid
                let _ = try await RoomsAPI.postReportMessage(
                    chatName: chatName,
                    messageId: message.id,
                    category: reason,
                    text: additionalInfo.isEmpty ? nil : additionalInfo
                )
            } catch {}
        }
    }
}
