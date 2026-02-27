//
//  ChatRoomView+Helpers.swift
//  XMPPChatUI
//

import SwiftUI

func chatIncomingBubbleBackground() -> Color {
    #if os(iOS)
    return Color(uiColor: .secondarySystemBackground)
    #else
    return Color(NSColor.controlBackgroundColor)
    #endif
}

func chatInputBackground() -> Color {
    #if os(iOS)
    return Color(uiColor: .systemBackground)
    #else
    return Color(NSColor.windowBackgroundColor)
    #endif
}

func chatSeparatorColor() -> Color {
    #if os(iOS)
    return Color(uiColor: .separator)
    #else
    return Color(NSColor.separatorColor)
    #endif
}

func onePixel() -> CGFloat {
    #if os(iOS)
    return 1.0 / UIScreen.main.scale
    #else
    return 1.0
    #endif
}

func chatBubbleMaxWidth() -> CGFloat {
    #if os(iOS)
    return UIScreen.main.bounds.width * 0.72
    #else
    return 480
    #endif
}

func inferMimeType(from url: String) -> String {
    let urlLower = url.lowercased()
    
    if urlLower.hasSuffix(".jpg") || urlLower.hasSuffix(".jpeg") {
        return "image/jpeg"
    } else if urlLower.hasSuffix(".png") {
        return "image/png"
    } else if urlLower.hasSuffix(".gif") {
        return "image/gif"
    } else if urlLower.hasSuffix(".webp") {
        return "image/webp"
    } else if urlLower.hasSuffix(".mp4") {
        return "video/mp4"
    } else if urlLower.hasSuffix(".mov") {
        return "video/quicktime"
    } else if urlLower.hasSuffix(".avi") {
        return "video/x-msvideo"
    } else if urlLower.hasSuffix(".pdf") {
        return "application/pdf"
    } else if urlLower.hasSuffix(".doc") || urlLower.hasSuffix(".docx") {
        return "application/msword"
    } else if urlLower.hasSuffix(".xls") || urlLower.hasSuffix(".xlsx") {
        return "application/vnd.ms-excel"
    } else if urlLower.hasSuffix(".txt") {
        return "text/plain"
    }
    
    return ""
}

func formatFileSize(_ sizeString: String) -> String {
    guard let size = Int64(sizeString) else {
        return "Unknown size"
    }
    
    if size < 1024 {
        return "\(size) B"
    } else if size < 1024 * 1024 {
        return String(format: "%.2f KB", Double(size) / 1024.0)
    } else if size < 1024 * 1024 * 1024 {
        return String(format: "%.2f MB", Double(size) / (1024.0 * 1024.0))
    } else {
        return String(format: "%.2f GB", Double(size) / (1024.0 * 1024.0 * 1024.0))
    }
}
