//
//  RootTabView.swift
//  SDKPlayground
//

import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var session: PlaygroundSession

    var body: some View {
        TabView {
            SetupView()
                .tabItem {
                    Label("Setup", systemImage: "gearshape.fill")
                }

            ChatTabView()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
                }

            LogsView()
                .tabItem {
                    Label("Logs", systemImage: "doc.text.fill")
                }
        }
    }
}
