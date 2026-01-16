//
//  FormatHelpers.swift
//  XMPPChatCore
//
//  Formatting utilities
//

import Foundation

public func formatNumberWithCommas(_ number: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
}

public func extractUniqueMembersFromRooms(_ rooms: [Room]) -> [User] {
    var uniqueUsers: [String: User] = [:]
    
    for room in rooms {
        // Extract users from room members if available
        // This is a placeholder - actual implementation depends on Room structure
    }
    
    return Array(uniqueUsers.values)
}

public func checkUniqueUsers(_ users: [User]) -> [User] {
    var seen: Set<String> = []
    return users.filter { user in
        if seen.contains(user.id) {
            return false
        }
        seen.insert(user.id)
        return true
    }
}

public func createUserNameFromSetUser(_ user: User) -> String {
    var name = ""
    if let firstName = user.firstName {
        name += firstName
    }
    if let lastName = user.lastName {
        if !name.isEmpty {
            name += " "
        }
        name += lastName
    }
    return name.isEmpty ? (user.email ?? "Unknown User") : name
}

public func dateComparison(_ date1: Date, _ date2: Date) -> ComparisonResult {
    return date1.compare(date2)
}

public func formatRelativeDate(_ date: Date) -> String {
    let calendar = Calendar.current
    let now = Date()
    
    if calendar.isDateInToday(date) {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    } else if calendar.isDateInYesterday(date) {
        return "Yesterday"
    } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    } else {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
