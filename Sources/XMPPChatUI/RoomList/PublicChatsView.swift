//
//  PublicChatsView.swift
//  XMPPChatUI
//
//  Directory of the app's public chats (GET /chats/public) so a chat can be
//  found and joined without a link or QR code. Mirrors PublicChatsModal on web.
//

import SwiftUI
import XMPPChatCore

@MainActor
final class PublicChatsViewModel: ObservableObject {
    enum Status: Equatable { case loading, loadingMore, done, error }

    @Published private(set) var items: [PublicChat] = []
    @Published private(set) var total = 0
    @Published private(set) var nextOffset = 0
    @Published private(set) var status: Status = .loading

    private var requestId = 0

    var hasMore: Bool { nextOffset < total }

    func load(offset: Int) async {
        requestId += 1
        let id = requestId
        status = offset > 0 ? .loadingMore : .loading
        do {
            let page = try await RoomsAPI.getPublicChats(offset: offset)
            guard id == requestId else { return }
            if offset > 0 {
                let seen = Set(items.map(\.name))
                items += page.items.filter { !seen.contains($0.name) }
            } else {
                items = page.items
            }
            total = page.total
            nextOffset = page.nextOffset
            status = .done
        } catch {
            guard id == requestId else { return }
            status = .error
        }
    }

    func cancel() {
        requestId += 1
    }
}

struct PublicChatsView: View {
    /// Names (JID local parts) of the chats the user is already in.
    let joinedNames: Set<String>
    let onOpen: (PublicChat) -> Void
    let onClose: () -> Void

    @StateObject private var model = PublicChatsViewModel()
    @State private var filter = ""

    private var visible: [PublicChat] {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return model.items }
        return model.items.filter {
            $0.title.lowercased().contains(needle) || $0.description.lowercased().contains(needle)
        }
    }

    var body: some View {
        NavigationView {
            List {
                switch model.status {
                case .loading:
                    HStack { ProgressView(); Text("Loading public chats...") }
                case .error:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Could not load the public chats.").foregroundColor(.red)
                        Button("Retry") { Task { await model.load(offset: model.nextOffset) } }
                    }
                case .done, .loadingMore:
                    if visible.isEmpty {
                        Text(filter.isEmpty || !model.hasMore
                             ? "There are no public chats to join yet."
                             : "No match so far. Load more to keep looking.")
                            .foregroundColor(.secondary)
                    }
                    ForEach(visible, id: \.name) { chat in
                        row(chat)
                    }
                    if model.hasMore {
                        Button {
                            Task { await model.load(offset: model.nextOffset) }
                        } label: {
                            HStack {
                                Spacer()
                                Text(model.status == .loadingMore ? "Loading..." : "Load more")
                                Spacer()
                            }
                        }
                        .disabled(model.status == .loadingMore)
                    }
                }
            }
            .searchable(text: $filter, prompt: "Filter public chats")
            .navigationTitle("Public chats")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
        .task { await model.load(offset: 0) }
        .onDisappear { model.cancel() }
    }

    private func row(_ chat: PublicChat) -> some View {
        let isJoined = joinedNames.contains(chat.name)
        return HStack(spacing: 12) {
            avatar(chat)
            VStack(alignment: .leading, spacing: 2) {
                Text(chat.title.isEmpty ? chat.name : chat.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if !chat.description.isEmpty {
                    Text(chat.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button(isJoined ? "Open" : "Join") { onOpen(chat) }
                .buttonStyle(.borderedProminent)
                .tint(isJoined ? .gray : .blue)
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private func avatar(_ chat: PublicChat) -> some View {
        let initial = String((chat.title.isEmpty ? chat.name : chat.title).prefix(1)).uppercased()
        if let url = URL(string: chat.picture), !chat.picture.isEmpty {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.blue.opacity(0.15)
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
        } else {
            Text(initial.isEmpty ? "#" : initial)
                .font(.headline)
                .foregroundColor(.blue)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.blue.opacity(0.15)))
        }
    }
}
