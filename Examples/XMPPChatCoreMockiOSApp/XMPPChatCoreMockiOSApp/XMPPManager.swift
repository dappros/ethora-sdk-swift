import Foundation
import XMPPChatCore

struct FlowLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let tag: FlowLogTag
    let message: String
    let payload: String?
}

enum FlowLogTag: String {
    case auth = "AUTH"
    case xmpp = "XMPP"
    case api = "API"
    case presence = "PRESENCE"
    case send = "SEND"
    case error = "ERROR"
    case system = "SYSTEM"
}

final class XMPPManager: NSObject, ObservableObject {
    @Published var connectionStatus: String = "offline"
    @Published var authStatus: String = "not_started"
    @Published var flowRunning: Bool = false
    @Published var lastEvent: String = "Ready"
    @Published var logs: [FlowLogEntry] = []
    @Published var rooms: [Room] = []
    @Published var activeRoomJID: String
    @Published var messageText: String = ""
    @Published var xmppUsername: String
    @Published var xmppPassword: String
    @Published var roomInput: String
    @Published var xmppDevServer: String
    @Published var xmppHost: String
    @Published var xmppConference: String

    private var client: XMPPClient?
    private var hasStarted = false
    private var flowTask: Task<Void, Never>?
    private var flowRunCount = 0
    private var loadedRoomJIDs: Set<String> = []

    override init() {
        let env = ProcessInfo.processInfo.environment
        self.xmppUsername = env["XMPP_USERNAME"] ?? ""
        self.xmppPassword = env["XMPP_PASSWORD"] ?? ""
        self.roomInput = env["XMPP_ROOM_JID"] ?? ""
        self.xmppDevServer = env["XMPP_DEV_SERVER"] ?? ""
        self.xmppHost = env["XMPP_HOST"] ?? ""
        self.xmppConference = env["XMPP_CONFERENCE"] ?? ""
        self.activeRoomJID = env["XMPP_ROOM_JID"] ?? ""
        super.init()
    }

    var activeRoomPresentInLoadedRooms: Bool {
        loadedRoomJIDs.contains(normalizedJID(activeRoomJID))
    }

    var canSendMessage: Bool {
        client != nil &&
        connectionStatus == ConnectionStatus.online.rawValue &&
        !activeRoomJID.isEmpty &&
        activeRoomPresentInLoadedRooms &&
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canRunFlow: Bool {
        !flowRunning &&
        !xmppUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !xmppPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !roomInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !xmppDevServer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !xmppHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !xmppConference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        runFlowTapped()
    }

    func runFlowTapped() {
        runFlow(reconnect: false)
    }

    func reconnectTapped() {
        runFlow(reconnect: true)
    }

    @MainActor
    func sendMessageTapped() {
        let message = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            appendLog(tag: .error, message: "Cannot send empty message")
            return
        }
        guard canSendMessage, let client = client else {
            appendLog(tag: .error, message: "Send blocked: flow not ready or room not joined")
            return
        }

        let user = UserStore.shared.currentUser
        let firstName = user?.firstName ?? "XMPP"
        let lastName = user?.lastName ?? "User"
        let photo = user?.profileImage ?? ""
        let walletAddress = user?.walletAddress ?? ""
        let customId = "ui-send-\(Int64(Date().timeIntervalSince1970 * 1000))"

        client.operations.sendTextMessage(
            roomJID: activeRoomJID,
            firstName: firstName,
            lastName: lastName,
            photo: photo,
            walletAddress: walletAddress,
            userMessage: message,
            customId: customId
        )

        appendLog(
            tag: .send,
            message: "Text message sent",
            payload: "room=\(activeRoomJID) id=\(customId) body=\(message)"
        )
        updateMain {
            self.messageText = ""
        }
    }

    func formattedLogsText() -> String {
        logs.map { entry in
            let ts = Self.logDateFormatter.string(from: entry.timestamp)
            if let payload = entry.payload, !payload.isEmpty {
                return "[\(ts)] [\(entry.tag.rawValue)] \(entry.message) | \(payload)"
            }
            return "[\(ts)] [\(entry.tag.rawValue)] \(entry.message)"
        }.joined(separator: "\n")
    }

    private func runFlow(reconnect: Bool) {
        guard !flowRunning else {
            appendLog(tag: .system, message: "Flow already running")
            return
        }

        flowTask?.cancel()
        flowTask = Task { [weak self] in
            guard let self = self else { return }
            await self.executeFlow(reconnect: reconnect)
        }
    }

    private func executeFlow(reconnect: Bool) async {
        let username = xmppUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = xmppPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawRoomInput = roomInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let devServer = xmppDevServer.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = xmppHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let conference = xmppConference.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !username.isEmpty, !password.isEmpty, !rawRoomInput.isEmpty,
              !devServer.isEmpty, !host.isEmpty, !conference.isEmpty else {
            appendLog(tag: .error, message: "Flow failed", payload: "Fill all XMPP config fields first")
            return
        }

        flowRunCount += 1
        updateMain {
            self.flowRunning = true
            self.authStatus = "starting"
            self.lastEvent = "Flow started"
        }
        appendLog(tag: .system, message: "Flow run #\(flowRunCount) started", payload: reconnect ? "mode=reconnect" : "mode=run")

        if reconnect, let existingClient = client {
            appendLog(tag: .xmpp, message: "Disconnecting existing XMPP client")
            await existingClient.disconnect()
            updateMain {
                self.client = nil
                ClientRegistry.shared.setGlobalXMPPClient(nil)
                self.connectionStatus = ConnectionStatus.offline.rawValue
            }
        }

        do {
            updateMain { self.authStatus = "manual_credentials" }
            appendLog(tag: .auth, message: "Using UI-provided XMPP credentials")

            let xmppSettings = XMPPSettings(
                devServer: devServer,
                host: host,
                conference: conference
            )

            let newClient = XMPPClient(
                username: username,
                password: password,
                settings: xmppSettings
            )
            newClient.delegate = self
            ClientRegistry.shared.setGlobalXMPPClient(newClient)
            updateMain {
                self.client = newClient
                self.connectionStatus = ConnectionStatus.connecting.rawValue
                self.authStatus = "connected_auth"
            }
            appendLog(tag: .xmpp, message: "XMPP client created", payload: "username=\(username)")

            appendLog(tag: .xmpp, message: "Waiting for isFullyConnected()")
            try await waitUntilFullyConnected(client: newClient, timeoutSeconds: 30)
            appendLog(tag: .xmpp, message: "XMPP fully connected")

            newClient.sendGlobalPresence()
            appendLog(tag: .presence, message: "Global presence sent")

            let resolvedRoomJID = roomJIDWithConferenceIfNeeded(rawRoomInput, conference: conference)
            if resolvedRoomJID != rawRoomInput {
                appendLog(tag: .system, message: "Auto-filled room conference domain", payload: resolvedRoomJID)
            }

            await newClient.sendPresenceToRoom(roomJID: resolvedRoomJID)
            appendLog(tag: .presence, message: "Presence sent to active room", payload: resolvedRoomJID)

            loadedRoomJIDs = [normalizedJID(resolvedRoomJID)]
            await MainActor.run {
                self.activeRoomJID = resolvedRoomJID
                RoomStore.shared.setActiveRoom(resolvedRoomJID)
                self.rooms = [
                    Room(
                        id: normalizedJID(resolvedRoomJID),
                        jid: resolvedRoomJID,
                        name: normalizedJID(resolvedRoomJID),
                        title: "Target Room"
                    )
                ]
            }

            updateMain {
                self.authStatus = "completed"
                self.lastEvent = "Flow completed"
                self.connectionStatus = newClient.status.rawValue
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            appendLog(tag: .error, message: "Flow failed", payload: message)
            updateMain {
                self.authStatus = "failed"
                self.lastEvent = "Flow failed: \(message)"
            }
        }

        updateMain {
            self.flowRunning = false
        }
    }

    private func waitUntilFullyConnected(client: XMPPClient, timeoutSeconds: TimeInterval) async throws {
        let startedAt = Date()
        while !client.isFullyConnected() {
            if Date().timeIntervalSince(startedAt) > timeoutSeconds {
                throw FlowError.connectionTimeout
            }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
    }

    private func roomJIDWithConferenceIfNeeded(_ raw: String, conference: String) -> String {
        if raw.contains("@") {
            return raw
        }
        return "\(raw)@\(conference)"
    }

    private func appendLog(tag: FlowLogTag, message: String, payload: String? = nil) {
        let entry = FlowLogEntry(timestamp: Date(), tag: tag, message: message, payload: payload)
        updateMain {
            self.logs.append(entry)
            self.lastEvent = message
        }
    }

    private func normalizedJID(_ jid: String) -> String {
        jid.components(separatedBy: "/").first ?? jid
    }

    private func updateMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    private enum FlowError: LocalizedError {
        case connectionTimeout

        var errorDescription: String? {
            switch self {
            case .connectionTimeout:
                return "Timed out waiting for full XMPP connection"
            }
        }
    }

    private static let logDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

extension XMPPManager: XMPPClientDelegate {
    func xmppClientDidConnect(_ client: XMPPClient) {
        appendLog(tag: .xmpp, message: "Delegate connected", payload: "username=\(client.username)")
        updateMain {
            self.connectionStatus = ConnectionStatus.online.rawValue
        }
    }

    func xmppClientDidDisconnect(_ client: XMPPClient) {
        appendLog(tag: .xmpp, message: "Delegate disconnected")
        updateMain {
            self.connectionStatus = ConnectionStatus.offline.rawValue
        }
    }

    func xmppClient(_ client: XMPPClient, didReceiveMessage message: Message) {
        appendLog(
            tag: .xmpp,
            message: "Incoming message",
            payload: "room=\(message.roomJid) body=\(message.body)"
        )
    }

    func xmppClient(_ client: XMPPClient, didReceiveStanza stanza: XMPPStanza) {
        let from = stanza.attributes["from"] ?? "n/a"
        let type = stanza.attributes["type"] ?? "n/a"
        let id = stanza.attributes["id"] ?? "n/a"
        let childNames = stanza.children.map(\.name).joined(separator: ",")
        appendLog(
            tag: .xmpp,
            message: "Incoming stanza",
            payload: "name=\(stanza.name) from=\(from) type=\(type) id=\(id) children=[\(childNames)]"
        )
    }

    func xmppClient(_ client: XMPPClient, didChangeStatus status: ConnectionStatus) {
        appendLog(tag: .xmpp, message: "Status changed", payload: status.rawValue)
        updateMain {
            self.connectionStatus = status.rawValue
        }
    }
}
