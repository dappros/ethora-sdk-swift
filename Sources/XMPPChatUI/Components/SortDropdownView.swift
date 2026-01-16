//
//  SortDropdownView.swift
//  XMPPChatUI
//
//  Sort dropdown component
//

import SwiftUI

public struct SortDropdownView: View {
    let options: [SortOption]
    @Binding var selectedOption: SortOption
    let onOptionSelected: ((SortOption) -> Void)?
    
    @State private var isOpen: Bool = false
    
    public init(
        options: [SortOption],
        selectedOption: Binding<SortOption>,
        onOptionSelected: ((SortOption) -> Void)? = nil
    ) {
        self.options = options
        self._selectedOption = selectedOption
        self.onOptionSelected = onOptionSelected
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation {
                    isOpen.toggle()
                }
            }) {
                HStack {
                    Text("Sort by: \(selectedOption.displayName)")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.caption)
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
                    ForEach(options, id: \.self) { option in
                        Button(action: {
                            selectedOption = option
                            onOptionSelected?(option)
                            withAnimation {
                                isOpen = false
                            }
                        }) {
                            HStack {
                                Text(option.displayName)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedOption == option {
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
}

public struct SortOption: Hashable {
    public let id: String
    public let displayName: String
    public let sortFunction: (Any, Any) -> Bool
    
    public init(id: String, displayName: String, sortFunction: @escaping (Any, Any) -> Bool) {
        self.id = id
        self.displayName = displayName
        self.sortFunction = sortFunction
    }
    
    public static func == (lhs: SortOption, rhs: SortOption) -> Bool {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
