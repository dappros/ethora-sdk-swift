//
//  MessageSearchModal.swift
//  XMPPChatUI
//
//  Message search sheet: query, sender and day filters, paged results.
//  Translated from src/components/Modals/MessageSearchModal/MessageSearchModal.tsx
//  and MessageHitResults.tsx
//

import SwiftUI
import XMPPChatCore

/// A room member offered in the sender filter.
public struct MessageSearchSender: Identifiable, Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct MessageSearchModal: View {
    @StateObject private var model: MessageSearchModel
    @Environment(\.presentationMode) private var presentationMode

    private let senders: [MessageSearchSender]
    private let onSelect: (MessageSearchHit) -> Void

    /// - Parameters:
    ///   - model: the search model, created with the open chat's room name
    ///   - senders: members for the sender filter
    ///   - onSelect: called with the hit the reader taps (the host opens it)
    public init(
        model: MessageSearchModel,
        senders: [MessageSearchSender] = [],
        onSelect: @escaping (MessageSearchHit) -> Void
    ) {
        _model = StateObject(wrappedValue: model)
        self.senders = senders
        self.onSelect = onSelect
    }

    public var body: some View {
        NavigationView {
            List {
                filtersSection
                resultsSection
            }
            .listStyle(.insetGrouped)
            .searchable(text: $model.text, prompt: "Search messages")
            .navigationTitle("Search")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Filters

    @ViewBuilder
    private var filtersSection: some View {
        Section {
            Picker("From", selection: $model.fromUserId) {
                Text("Anyone").tag(String?.none)
                ForEach(senders) { sender in
                    Text(sender.name).tag(Optional(sender.id))
                }
            }

            dayRow(title: "Sent after", date: $model.sinceDay)
            dayRow(title: "Sent before", date: $model.untilDay)

            if model.hasBackwardsRange {
                Text("The start date is after the end date.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    @ViewBuilder
    private func dayRow(title: String, date: Binding<Date?>) -> some View {
        Toggle(title, isOn: Binding(
            get: { date.wrappedValue != nil },
            set: { enabled in
                date.wrappedValue = enabled ? (date.wrappedValue ?? Date()) : nil
            }
        ))
        if let value = date.wrappedValue {
            DatePicker(
                "Day",
                selection: Binding(
                    get: { value },
                    set: { date.wrappedValue = $0 }
                ),
                displayedComponents: .date
            )
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsSection: some View {
        Section {
            switch model.state.status {
            case .idle:
                if model.trimmedText.count < MessageSearchQuery.minQueryLength {
                    Text("Type at least \(MessageSearchQuery.minQueryLength) characters to search.")
                        .foregroundColor(.secondary)
                }
            case .loading:
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            case .error:
                HStack {
                    Text("Search failed.")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Retry") { model.retry() }
                }
            case .done, .loadingMore:
                if model.state.items.isEmpty && model.state.status == .done {
                    Text("No results found")
                        .foregroundColor(.secondary)
                } else {
                    if model.state.total > 0 {
                        Text("\(model.state.total) results")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    ForEach(model.state.items, id: \.key) { hit in
                        Button {
                            onSelect(hit)
                        } label: {
                            MessageSearchResultRow(hit: hit, senderName: senderName(for: hit), query: model.trimmedText)
                        }
                        .buttonStyle(.plain)
                    }
                    if model.state.status == .loadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if model.hasMore {
                        Button("Show more") { model.loadMore() }
                    }
                }
            }
        }
    }

    private func senderName(for hit: MessageSearchHit) -> String {
        if let sender = senders.first(where: { $0.id == hit.fromUserId }) {
            return sender.name
        }
        // The `from` JID is `appId_userId@host`: show what is left after the app prefix.
        let local = hit.from.components(separatedBy: "@").first ?? hit.from
        return local.components(separatedBy: "_").last ?? local
    }
}

/// One search hit: sender, time and the body with the query highlighted.
struct MessageSearchResultRow: View {
    let hit: MessageSearchHit
    let senderName: String
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(senderName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                if let date = hit.createdDate {
                    Text(Self.formatter.string(from: date))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Text(highlighted)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var highlighted: AttributedString {
        var attributed = AttributedString(hit.body)
        guard !query.isEmpty,
              let range = hit.body.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]),
              let attributedRange = Range(range, in: attributed) else {
            return attributed
        }
        attributed[attributedRange].backgroundColor = .yellow
        attributed[attributedRange].foregroundColor = .black
        return attributed
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
