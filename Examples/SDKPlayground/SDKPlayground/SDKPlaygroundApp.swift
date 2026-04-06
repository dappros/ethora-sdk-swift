//
//  SDKPlaygroundApp.swift
//  SDKPlayground
//
//  Local playground app for Ethora Swift SDK (XMPPChatCore + XMPPChatUI).
//

import SwiftUI

@main
struct SDKPlaygroundApp: App {
    @StateObject private var session = PlaygroundSession()
    @StateObject private var logs = PlaygroundLogStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(session)
                .environmentObject(logs)
        }
    }
}
