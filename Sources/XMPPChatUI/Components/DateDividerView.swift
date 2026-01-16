//
//  DateDividerView.swift
//  XMPPChatUI
//
//  Custom date divider component
//

import SwiftUI
import XMPPChatCore

public struct DateDividerView: View {
    let date: Date
    let customComponent: ((DaySeparatorProps) -> AnyView)?
    
    public init(
        date: Date,
        customComponent: ((DaySeparatorProps) -> AnyView)? = nil
    ) {
        self.date = date
        self.customComponent = customComponent
    }
    
    public var body: some View {
        if let customComponent = customComponent {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return AnyView(customComponent(DaySeparatorProps(date: date, formattedDate: formatter.string(from: date))))
        } else {
            return AnyView(DefaultDateDivider(date: date))
        }
    }
}

struct DefaultDateDivider: View {
    let date: Date
    
    var body: some View {
        HStack {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 1)
            
            Text(formatDate(date))
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                #if os(iOS)
                .background(Color(uiColor: .systemGray6))
                #else
                .background(Color(NSColor.controlBackgroundColor))
                #endif
                .cornerRadius(12)
            
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 1)
        }
        .padding(.vertical, 8)
    }
    
    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
}
