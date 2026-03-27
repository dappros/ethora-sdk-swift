import SwiftUI

@main
struct XMPPChatCoreMockiOSApp: App {
    @StateObject private var xmppManager = XMPPManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(xmppManager)
                .onAppear {
                    xmppManager.startIfNeeded()
                }
        }
    }
}
