//
//  CallLogRowView.swift
//  XMPPChatUI
//
//  Centered chat row for a finished call ("Outgoing call · 12 sec", "Missed call").
//  Rendered from CallLogMeta, so the wording follows the viewer's direction.
//

import SwiftUI
import XMPPChatCore

struct CallLogRowView: View {
    let callLog: CallLogMeta

    var body: some View {
        let selfUsername = UserStore.shared.currentUser?.xmppUsername ?? ""
        let outgoing = callLog.isOutgoing(selfXmppUsername: selfUsername)
        let label = CallLogFormatter.label(for: callLog, selfXmppUsername: selfUsername)

        HStack(spacing: 6) {
            Image(systemName: callLog.kind == .video ? "video.fill" : "phone.fill")
                .font(.caption)
                .foregroundColor(callLog.isMissed && !outgoing ? .red : .secondary)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
