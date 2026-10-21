// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "XMPPChatSwift",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "XMPPChatCore",
            targets: ["XMPPChatCore"]),
        .library(
            name: "XMPPChatUI",
            targets: ["XMPPChatUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.0"),
        // LiveKit native SDK for 1:1 audio/video calls (XMPPChatUI only).
        // Pinned to the 2.13 line: 2.13 declares swift-tools 5.9 and iOS 13,
        // matching this package's toolchain floor. Newer LiveKit releases need
        // swift-tools 6.x.
        .package(url: "https://github.com/livekit/client-sdk-swift.git", .upToNextMinor(from: "2.13.0")),
        // The WebRTC build LiveKit already links. Declared directly so the 1:1
        // peer to peer calls (RTCPeerConnection) use the same binary instead of
        // shipping a second WebRTC. Must match the exact pin in LiveKit 2.13's
        // own Package.swift.
        .package(url: "https://github.com/livekit/webrtc-xcframework.git", exact: "144.7559.03"),
    ],
    targets: [
        .target(
            name: "XMPPChatCore",
            dependencies: [
                .product(name: "Starscream", package: "Starscream"),
            ]),
        .target(
            name: "XMPPChatUI",
            dependencies: [
                "XMPPChatCore",
                .product(name: "LiveKit", package: "client-sdk-swift"),
                .product(name: "LiveKitWebRTC", package: "webrtc-xcframework"),
            ]),
        .testTarget(
            name: "XMPPChatCoreTests",
            dependencies: ["XMPPChatCore"]),
        // L2 / ViewModel-level tests target XMPPChatUI's ObservableObject
        // ViewModels. Kept separate from XMPPChatCoreTests so adding a
        // SwiftUI dependency here doesn't leak into the Core test target,
        // which intentionally stays UI-framework-free.
        .testTarget(
            name: "XMPPChatUITests",
            dependencies: ["XMPPChatUI", "XMPPChatCore"]),
    ]
)
