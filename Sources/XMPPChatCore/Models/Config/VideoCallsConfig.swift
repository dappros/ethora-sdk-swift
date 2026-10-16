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
    /// LiveKit server URL (wss://...). Required; without it the call buttons
    /// show a configuration error.
    public var livekitUrl: String
    /// Room types that can place calls. Only "private" (1:1) is supported.
    public var allowedRoomTypes: [String]
    /// Show an audio-only call button next to the video button.
    public var enableAudioCalls: Bool
    /// Publish the camera as soon as a video call connects. Default true.
    public var startWithCameraOn: Bool
    /// Publish the microphone as soon as a call connects. Default true.
    public var startWithMicOn: Bool

    public init(
        enabled: Bool = false,
        livekitUrl: String = "",
        allowedRoomTypes: [String] = ["private"],
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
    /// and private rooms are allowed.
    public var isCallingAvailable: Bool {
        enabled
            && !livekitUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && allowedRoomTypes.contains("private")
    }
}
