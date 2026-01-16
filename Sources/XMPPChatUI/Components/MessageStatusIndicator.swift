//
//  MessageStatusIndicator.swift
//  XMPPChatUI
//
//  Message status indicators (sending, sent, failed)
//

import SwiftUI
import XMPPChatCore

public struct MessageStatusIndicator: View {
    let status: MessageStatus
    
    public init(status: MessageStatus) {
        self.status = status
    }
    
    public var body: some View {
        Group {
            switch status {
            case .sending:
                ProgressView()
                    .scaleEffect(0.7)
            case .sent:
                Image(systemName: "checkmark")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            case .delivered:
                Image(systemName: "checkmark.circle")
                    .font(.caption2)
                    .foregroundColor(.blue)
            case .read:
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.blue)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
    }
}

public enum MessageStatus {
    case sending
    case sent
    case delivered
    case read
    case failed
}
