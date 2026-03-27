import SwiftUI
import XMPPChatCore
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @EnvironmentObject private var xmppManager: XMPPManager

    var body: some View {
        TabView {
            flowTab
                .tabItem {
                    Label("Flow", systemImage: "bolt.horizontal.circle")
                }

            logsTab
                .tabItem {
                    Label("Logs", systemImage: "text.alignleft")
                }
        }
    }

    private var flowTab: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("JWT-Driven XMPP Mock")
                        .font(.headline)

                    HStack(spacing: 8) {
                        badge("Auth: \(xmppManager.authStatus)", color: authColor)
                        badge("XMPP: \(xmppManager.connectionStatus)", color: connectionColor)
                        if xmppManager.flowRunning {
                            badge("RUNNING", color: .orange)
                        }
                    }

                    HStack(spacing: 10) {
                        Button("Run Flow") {
                            xmppManager.runFlowTapped()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!xmppManager.canRunFlow)

                        Button("Reconnect") {
                            xmppManager.reconnectTapped()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!xmppManager.canRunFlow)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("XMPP Config")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        TextField("XMPP Username", text: $xmppManager.xmppUsername)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("XMPP Password", text: $xmppManager.xmppPassword)
                            .textFieldStyle(.roundedBorder)
                        TextField("Room ID or Full Room JID", text: $xmppManager.roomInput)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("XMPP WS URL (devServer)", text: $xmppManager.xmppDevServer)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("XMPP Host", text: $xmppManager.xmppHost)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("XMPP Conference Domain", text: $xmppManager.xmppConference)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Active Room")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(xmppManager.activeRoomJID)
                            .font(.footnote)
                            .textSelection(.enabled)
                        if !xmppManager.activeRoomPresentInLoadedRooms {
                            Text("Target room is not in /chats/my; send is disabled.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rooms from /chats/my (\(xmppManager.rooms.count))")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        if xmppManager.rooms.isEmpty {
                            Text("No rooms loaded")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(xmppManager.rooms, id: \.jid) { room in
                                HStack(spacing: 8) {
                                    Image(systemName: room.jid == xmppManager.activeRoomJID ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(room.jid == xmppManager.activeRoomJID ? .blue : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(room.title)
                                            .font(.footnote)
                                            .lineLimit(1)
                                        Text(room.jid)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Send Text Message")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        TextField("Type message", text: $xmppManager.messageText)
                            .textFieldStyle(.roundedBorder)

                        Button("Send") {
                            xmppManager.sendMessageTapped()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!xmppManager.canSendMessage)
                    }

                    Text("Last Event: \(xmppManager.lastEvent)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .navigationTitle("Flow")
        }
    }

    private var logsTab: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Text("Logs (\(xmppManager.logs.count))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Button("Copy All") {
#if canImport(UIKit)
                        UIPasteboard.general.string = xmppManager.formattedLogsText()
#endif
                    }
                    .buttonStyle(.bordered)
                }
                .padding([.top, .horizontal])

                if xmppManager.logs.isEmpty {
                    VStack {
                        Spacer()
                        Text("No logs yet")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(xmppManager.logs) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(logLine(entry))
                                        .font(.caption)
                                        .textSelection(.enabled)
                                    if let payload = entry.payload, !payload.isEmpty {
                                        Text(payload)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .textSelection(.enabled)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Logs")
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private var authColor: Color {
        switch xmppManager.authStatus {
        case "completed", "authorized":
            return .green
        case "failed":
            return .red
        case "authorizing", "starting":
            return .orange
        default:
            return .secondary
        }
    }

    private var connectionColor: Color {
        switch xmppManager.connectionStatus {
        case ConnectionStatus.online.rawValue:
            return .green
        case ConnectionStatus.error.rawValue:
            return .red
        case ConnectionStatus.connecting.rawValue:
            return .orange
        default:
            return .secondary
        }
    }

    private func logLine(_ entry: FlowLogEntry) -> String {
        let ts = Self.timeFormatter.string(from: entry.timestamp)
        return "[\(ts)] [\(entry.tag.rawValue)] \(entry.message)"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
