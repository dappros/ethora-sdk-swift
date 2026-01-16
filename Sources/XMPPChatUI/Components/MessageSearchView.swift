//
//  MessageSearchView.swift
//  XMPPChatUI
//
//  Message search component
//

import SwiftUI
import XMPPChatCore

public struct MessageSearchView: View {
    let messages: [Message]
    let onMessageSelected: (Message) -> Void
    
    @State private var searchText: String = ""
    @State private var searchResults: [Message] = []
    @State private var selectedIndex: Int = 0
    @FocusState private var isSearchFocused: Bool
    
    public init(
        messages: [Message],
        onMessageSelected: @escaping (Message) -> Void
    ) {
        self.messages = messages
        self.onMessageSelected = onMessageSelected
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Search Input
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search messages...", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onChange(of: searchText) { newValue in
                        performSearch(query: newValue)
                    }
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        searchResults = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            #if os(iOS)
            .background(Color(uiColor: .systemGray6))
            #else
            .background(Color(NSColor.controlBackgroundColor))
            #endif
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            // Search Results Count
            if !searchResults.isEmpty {
                HStack {
                    Text("\(selectedIndex + 1) of \(searchResults.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Navigation buttons
                    HStack(spacing: 8) {
                        Button(action: {
                            navigateToPrevious()
                        }) {
                            Image(systemName: "chevron.up")
                                .font(.caption)
                        }
                        .disabled(selectedIndex == 0)
                        
                        Button(action: {
                            navigateToNext()
                        }) {
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .disabled(selectedIndex >= searchResults.count - 1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            
            // Results List
            if !searchResults.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, message in
                            SearchResultRow(
                                message: message,
                                searchText: searchText,
                                isSelected: index == selectedIndex,
                                onTap: {
                                    selectedIndex = index
                                    onMessageSelected(message)
                                }
                            )
                        }
                    }
                }
            } else if !searchText.isEmpty {
                VStack {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No results found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        #if os(iOS)
        .background(Color(uiColor: .systemBackground))
        #else
        .background(Color(NSColor.controlBackgroundColor))
        #endif
    }
    
    private func performSearch(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            selectedIndex = 0
            return
        }
        
        let lowercasedQuery = query.lowercased()
        searchResults = messages.filter { message in
            message.body.lowercased().contains(lowercasedQuery)
        }
        selectedIndex = 0
        
        if !searchResults.isEmpty {
            onMessageSelected(searchResults[0])
        }
    }
    
    private func navigateToPrevious() {
        guard selectedIndex > 0 else { return }
        selectedIndex -= 1
        onMessageSelected(searchResults[selectedIndex])
    }
    
    private func navigateToNext() {
        guard selectedIndex < searchResults.count - 1 else { return }
        selectedIndex += 1
        onMessageSelected(searchResults[selectedIndex])
    }
}

struct SearchResultRow: View {
    let message: Message
    let searchText: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.user.fullName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(formatDate(message.date))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Text(highlightedText)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
    
    private var highlightedText: AttributedString {
        var attributed = AttributedString(message.body)
        let lowercasedBody = message.body.lowercased()
        let lowercasedQuery = searchText.lowercased()
        
        if let range = lowercasedBody.range(of: lowercasedQuery) {
            if let attributedRange = Range(range, in: attributed) {
                attributed[attributedRange].backgroundColor = .yellow
                attributed[attributedRange].foregroundColor = .black
            }
        }
        
        return attributed
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
