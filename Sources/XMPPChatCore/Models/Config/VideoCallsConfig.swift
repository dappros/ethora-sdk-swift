//
//  VideoCallsConfig.swift
//  XMPPChatCore
//
//  Mirrors `videoCalls` in the web IConfig (src/types/models/config.model.ts,
//  VideoCallsConfig). Off by default. Key names match the web config so one
//  config payload works on every SDK.
//

import Foundation

public struct VideoCallsConfig: Equatable {
    /// Master switch. Calls are unavailable unless this is true.
    public var enabled: Bool
    /// LiveKit server URL (wss://...). Used for LiveKit calls when the server
    /// does not send its own `livekitUrl` on the call-token. Peer to peer 1:1
    /// calls do not need it.
    public var livekitUrl: String
    /// Room types that can place and receive calls: "private" (1:1) and "group"
    /// (members-only group chats, always LiveKit). Default is both; pass
    /// `["private"]` to keep calls 1:1 only. Public rooms never call.
    public var allowedRoomTypes: [String]
    /// Show an audio-only call button next to the video button.
    public var enableAudioCalls: Bool
    /// Publish the camera as soon as a video call connects. Default true.
    public var startWithCameraOn: Bool
    /// Publish the microphone as soon as a call connects. Default true.
    public var startWithMicOn: Bool

    public static let defaultAllowedRoomTypes = ["private", "group"]

    public init(
        enabled: Bool = false,
        livekitUrl: String = "",
        allowedRoomTypes: [String] = VideoCallsConfig.defaultAllowedRoomTypes,
        enableAudioCalls: Bool = false,
        startWithCameraOn: Bool = true,
        startWithMicOn: Bool = true
    ) {
        self.enabled = enabled
        self.livekitUrl = livekitUrl
        self.allowedRoomTypes = allowedRoomTypes
        self.enableAudioCalls = enableAudioCalls
        self.startWithCameraOn = startWithCameraOn
        self.startWithMicOn = startWithMicOn
    }

    /// True when calls can be placed at all: enabled, a LiveKit URL is set,
    /// and private rooms are allowed. The URL stays required for now (same rule
    /// as the web and React Native SDKs) because group calls run on LiveKit,
    /// even though a peer to peer 1:1 call itself does not use it.
    public var isCallingAvailable: Bool {
        enabled
            && !livekitUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (allowedRoomTypes.contains("private") || allowedRoomTypes.contains("group"))
    }

    /// Whether a room of this type may start and receive calls under
    /// `allowedRoomTypes`. Public rooms (and unknown types) never can.
    public func allowsCalls(in type: RoomType?) -> Bool {
        guard let type, type == .private || type == .group else { return false }
        return allowedRoomTypes.contains(type.rawValue)
    }
}
