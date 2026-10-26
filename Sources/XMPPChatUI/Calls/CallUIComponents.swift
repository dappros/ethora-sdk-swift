//
//  CallUIComponents.swift
//  XMPPChatUI
//
//  Small views shared by the LiveKit, group and p2p call screens: control
//  buttons, the elapsed-time label, the participant tile and the minimized
//  strip. Mirrors the shared pieces of src/components/VideoCalls.
//

import SwiftUI
import XMPPChatCore

/// Elapsed call time ("mm:ss" or "h:mm:ss") ticking every second.
struct CallTimerText: View {
    let since: Date?

    static func format(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60
        let secs = safe % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%02d:%02d", minutes, secs)
    }

    var body: some View {
        if let since {
            TimelineView(.periodic(from: since, by: 1)) { context in
                Text(Self.format(Int(context.date.timeIntervalSince(since))))
                    .monospacedDigit()
            }
        }
    }
}

/// Round control button used on every call screen.
struct CallControlButton: View {
    let systemImage: String
    let label: String
    var tint: Color = Color.white.opacity(0.18)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(tint))
        }
        .accessibilityLabel(label)
    }
}

/// Dismissible banner for a camera / microphone problem.
struct CallDeviceBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(message)
                .font(.footnote)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark").foregroundColor(.white)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.red.opacity(0.9))
        )
        .padding(.top, 12)
    }
}

/// Minimize button shown in the corner of a full-screen call.
struct CallMinimizeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.white.opacity(0.18)))
        }
        .accessibilityLabel("Minimize call")
    }
}

/// The call while minimized: a strip over the top of the app with the name,
/// the elapsed time, and expand / hang-up buttons. The media session stays
/// mounted behind it.
struct CallMinimizedStrip: View {
    let title: String
    let subtitle: String
    let connectedAt: Date?
    let onExpand: () -> Void
    let onHangup: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onExpand) {
                HStack(spacing: 10) {
                    Image(systemName: "phone.fill").foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title.isEmpty ? "Call" : title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(subtitle)
                            CallTimerText(since: connectedAt)
                        }
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.75))
                    }
                    Spacer(minLength: 0)
                }
            }
            .accessibilityLabel("Expand call")

            Button(action: onHangup) {
                Image(systemName: "phone.down.fill")
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.red))
            }
            .accessibilityLabel("End call")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.12))
        )
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
    }
}

/// Initials in a circle, used when a participant has no live video.
struct CallAvatar: View {
    let name: String
    var size: CGFloat = 64

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0).uppercased() }.joined()
        return letters.isEmpty ? "?" : letters
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color(red: 0, green: 0.32, blue: 0.8)))
    }
}

/// Red "microphone is off" badge.
struct CallMicOffBadge: View {
    var body: some View {
        Image(systemName: "mic.slash.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 18, height: 18)
            .background(Circle().fill(Color(red: 0.9, green: 0.22, blue: 0.21)))
            .accessibilityLabel("Microphone is off")
    }
}
