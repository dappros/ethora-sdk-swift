//
//  SendGetHistory.swift
//  XMPPChatCore
//
//  MAM page queries. Fire-and-forget paging (`sendGetHistory`) hands its rows to
//  StanzaHandlers.onMessageHistory, and the closing <fin> moves the paging
//  cursor. `fetchHistoryPage` waits for the answer, for a jump window or a time
//  lookup. Translated from xmppClient.ts requestMamHistory and getHistory.xmpp.ts.
//

import Foundation

extension XMPPOperations {

    /// Sends a latest or older page query. Rows arrive through
    /// StanzaHandlers.onMessageHistory; the `<fin>` moves the paging cursor.
    /// - Parameters:
    ///   - chatJID: Room JID (or a bare room name, the domain is added)
    ///   - max: Maximum number of rows to return
    ///   - before: Archive id to page back from (exclusive). nil asks for the latest page.
    ///   - otherId: Optional query id. Must start with `get-history:` for the paging state to follow it.
    public func sendGetHistory(
        chatJID: String,
        max: Int,
        before: Int64? = nil,
        otherId: String? = nil
    ) {
        guard let client else { return }
        let validBefore: Int64? = (before ?? 0) > 0 ? before : nil
        let queryId = otherId ?? "get-history:\(UUID().uuidString)"
        let query = MamQuery(
            chatJID: fixedRoomJID(chatJID, client: client),
            queryId: queryId,
            max: max,
            before: validBefore
        )

        mamQueries.noteRequest(queryId: queryId, before: validBefore)
        guard let stream = client.xmppStream else {
            mamQueries.noteRequest(queryId: queryId, before: nil)
            NotificationCenter.default.post(
                name: NSNotification.Name("XMPPHistoryLoadFailed"),
                object: nil,
                userInfo: ["error": "Not connected", "roomJID": chatJID]
            )
            return
        }
        stream.send(query.stanza())
        print("[XMPPOperations] get-history room=\(query.chatJID) max=\(max) before=\(validBefore.map(String.init) ?? "latest")")
    }

    /// Sends a page query and waits for its answer.
    ///
    /// Used for a jump window (`before` and `after` around a target) and for a
    /// time lookup (`start`/`end`). The result never writes the paging cursor.
    /// A refused, failed or silent query resolves with `fin == nil`.
    public func fetchHistoryPage(
        chatJID: String,
        max: Int,
        before: Int64? = nil,
        after: Int64? = nil,
        start: String? = nil,
        end: String? = nil,
        timeout: TimeInterval = 10
    ) async -> MamQueryRegistry.PageResult {
        guard let client else {
            return MamQueryRegistry.PageResult(messages: [], fin: nil)
        }
        let queryId = "window:\(UUID().uuidString)"
        let query = MamQuery(
            chatJID: fixedRoomJID(chatJID, client: client),
            queryId: queryId,
            max: max,
            before: before,
            after: after,
            start: start,
            end: end
        )
        return await mamQueries.run(queryId: queryId, timeout: timeout) {
            guard let stream = client.xmppStream else { return false }
            stream.send(query.stanza())
            return true
        }
    }

    private func fixedRoomJID(_ chatJID: String, client: XMPPClient) -> String {
        chatJID.contains("@") ? chatJID : "\(chatJID)@\(client.conference)"
    }
}
