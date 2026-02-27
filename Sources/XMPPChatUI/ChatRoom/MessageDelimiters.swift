//
//  MessageDelimiters.swift
//  XMPPChatUI
//

import SwiftUI
import XMPPChatCore

// MARK: - Unread Messages Delimiter
struct UnreadMessagesDelimiter: View {
    var body: some View {
        HStack {
            Rectangle()
                .fill(Color.red)
                .frame(height: 1)
            
            Text("New Messages")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.red)
                .padding(.horizontal, 8)
            
            Rectangle()
                .fill(Color.red)
                .frame(height: 1)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Date Separator
struct DateSeparatorView: View {
    let date: Date
    
    var body: some View {
        HStack {
            line
            Text(formattedDate)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.gray.opacity(0.15))
                )
            line
        }
        .padding(.horizontal)
    }
    
    private var line: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 1)
    }
    
    private var formattedDate: String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return "Today"
        }
        
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        
        let currentYear = calendar.component(.year, from: now)
        let messageYear = calendar.component(.year, from: date)
        
        let formatter = DateFormatter()
        
        if currentYear == messageYear {
            formatter.dateFormat = "d MMMM"
        } else {
            formatter.dateFormat = "d MMMM yyyy"
        }
        
        let day = calendar.component(.day, from: date)
        let ordinalDay = ordinalSuffix(for: day)
        
        if currentYear == messageYear {
            formatter.dateFormat = "MMMM"
            let month = formatter.string(from: date)
            return "\(ordinalDay) \(month)"
        } else {
            formatter.dateFormat = "MMMM yyyy"
            let monthYear = formatter.string(from: date)
            return "\(ordinalDay) \(monthYear)"
        }
    }
    
    private func ordinalSuffix(for day: Int) -> String {
        let suffix: String
        switch day {
        case 1, 21, 31:
            suffix = "st"
        case 2, 22:
            suffix = "nd"
        case 3, 23:
            suffix = "rd"
        default:
            suffix = "th"
        }
        return "\(day)\(suffix)"
    }
}

// Helper function to determine if date separator should be shown
func shouldShowDateSeparator(currentMessage: Message, previousMessage: Message?) -> Bool {
    guard let previous = previousMessage else {
        return true
    }
    
    if currentMessage.id == "delimiter-new" || previous.id == "delimiter-new" {
        return false
    }
    
    let calendar = Calendar.current
    return !calendar.isDate(currentMessage.date, inSameDayAs: previous.date)
}
