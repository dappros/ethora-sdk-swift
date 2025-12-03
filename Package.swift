// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "XMPPChatSwift",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "XMPPChatCore",
            targets: ["XMPPChatCore"]),
        .library(
            name: "XMPPChatUI",
            targets: ["XMPPChatUI"]),
        .executable(
            name: "XMPPChatApp",
            targets: ["XMPPChatApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.0"),
    ],
    targets: [
        .target(
            name: "XMPPChatCore",
            dependencies: [
                .product(name: "Starscream", package: "Starscream"),
            ]),
        .target(
            name: "XMPPChatUI",
            dependencies: ["XMPPChatCore"]),
        .executableTarget(
            name: "XMPPChatApp",
            dependencies: ["XMPPChatCore"]),
    ]
)

