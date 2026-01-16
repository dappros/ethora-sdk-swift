//
//  SelectView.swift
//  XMPPChatUI
//
//  Custom select dropdown
//

import SwiftUI

public struct SelectView<Item: Hashable & CustomStringConvertible>: View {
    let title: String
    let items: [Item]
    @Binding var selection: Item
    let allowsSearch: Bool
    
    @State private var isOpen: Bool = false
    @State private var searchText: String = ""
    
    public init(
        title: String,
        items: [Item],
        selection: Binding<Item>,
        allowsSearch: Bool = false
    ) {
        self.title = title
        self.items = items
        self._selection = selection
        self.allowsSearch = allowsSearch
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation {
                    isOpen.toggle()
                }
            }) {
                HStack {
                    Text(title)
                        .foregroundColor(.primary)
                    Spacer()
                    Text(selection.description)
                        .foregroundColor(.secondary)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                #if os(iOS)
                .background(Color(uiColor: .systemGray6))
                #else
                .background(Color(NSColor.controlBackgroundColor))
                #endif
            }
            
            if isOpen {
                VStack(alignment: .leading, spacing: 0) {
                    if allowsSearch {
                        TextField("Search...", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .padding()
                    }
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredItems, id: \.self) { item in
                                Button(action: {
                                    selection = item
                                    withAnimation {
                                        isOpen = false
                                    }
                                }) {
                                    HStack {
                                        Text(item.description)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        if selection == item {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(.plain)
                                
                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
                #if os(iOS)
                .background(Color(uiColor: .systemBackground))
                #else
                .background(Color(NSColor.controlBackgroundColor))
                #endif
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private var filteredItems: [Item] {
        if searchText.isEmpty {
            return items
        }
        let query = searchText.lowercased()
        return items.filter { $0.description.lowercased().contains(query) }
    }
}
