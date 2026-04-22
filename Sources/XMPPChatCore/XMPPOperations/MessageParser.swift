import Foundation

// MARK: - Supporting Models

public struct MessageData {
    public let id: String
    public let body: String?
    public let roomJid: String
    public let date: Date
    public let userWallet: String
    public let photoURL: String
    public let dataAttrs: [String: String]
    public let deleted: Bool
    public let translations: [String: String]?
    public let langSource: String?
    public let xmppId: String?
    public let xmppFrom: String?

    public init(id: String,
                body: String?,
                roomJid: String,
                date: Date,
                userWallet: String,
                photoURL: String,
                dataAttrs: [String: String],
                deleted: Bool,
                translations: [String: String]?,
                langSource: String?,
                xmppId: String?,
                xmppFrom: String?) {
        self.id = id
        self.body = body
        self.roomJid = roomJid
        self.date = date
        self.userWallet = userWallet
        self.photoURL = photoURL
        self.dataAttrs = dataAttrs
        self.deleted = deleted
        self.translations = translations
        self.langSource = langSource
        self.xmppId = xmppId
        self.xmppFrom = xmppFrom
    }
}

// MARK: - Message Parser

public final class MessageParser {

    public static func getDataFromStanza(_ stanza: XMPPStanza) -> MessageData? {
        
        // Try to extract inner message from MAM structure: result (xmlns='urn:xmpp:mam:2') -> forwarded -> message
        var fullData: XMPPStanza = stanza
        
        // Check if this is a MAM result message
        if let result = stanza.getChild("result", xmlns: "urn:xmpp:mam:2") {
            if let forwarded = result.getChild("forwarded", xmlns: "urn:xmpp:forward:0") {
                if let innerMessage = forwarded.getChild("message") {
                    fullData = innerMessage
                }
            } else if let forwarded = result.getChild("forwarded") {
                if let innerMessage = forwarded.getChild("message") {
                    fullData = innerMessage
                }
            }
        } else if let result = stanza.getChild("result") {
            if let forwarded = result.getChild("forwarded") {
                if let innerMessage = forwarded.getChild("message") {
                    fullData = innerMessage
                }
            }
        }

        let xmppId = fullData.attributes["id"]
        let xmppFrom = fullData.attributes["from"] ?? ""

        let fromParts = xmppFrom.split(separator: "/").map(String.init)
        let roomJid = fromParts.first ?? ""
        let userWallet = fromParts.count >= 2 ? fromParts[1] : roomJid

        // ID extraction - get from result element (MAM) or from stanza itself
        var id: String? = nil

        if let r = stanza.getChild("result", xmlns: "urn:xmpp:mam:2") ?? stanza.getChild("result") {
            id = r.attributes["id"]
        }

        if id == nil {
            if let stanzaIdEl = fullData.getChild("stanza-id"),
               let sid = stanzaIdEl.attributes["id"] {
                id = sid.count >= 16 ? String(sid.suffix(16)) : sid
            }
        }

        let finalId = id ?? xmppId ?? "\(Int64(Date().timeIntervalSince1970 * 1000))"

        let body = fullData.getChild("body")?.text
        let deleted = (fullData.getChild("deleted") != nil)
        
        // translations
        var translations: [String: String]? = nil
        if let tNode = fullData.getChild("translations"),
           let raw = tNode.attributes["value"],
           let jsonData = raw.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let arr = json["translates"] as? [[String: Any]] {

            var map: [String: String] = [:]
            for item in arr {
                if let lang = item["lang"] as? String,
                   let text = item["text"] as? String {
                    map[lang] = text
                }
            }
            translations = map.isEmpty ? nil : map
        }

        let langSource = fullData.getChild("translate")?.attributes["source"]

        // date parsing
        let regex = try! NSRegularExpression(pattern: "\\d{13,}")
        var date = Date()

        if let match = regex.firstMatch(in: finalId, range: NSRange(location: 0, length: finalId.count)) {
            let num = (finalId as NSString).substring(with: match.range)
            if let ts = Int64(num.prefix(13)) {
                date = Date(timeIntervalSince1970: TimeInterval(ts) / 1000)
            }
        }

        let dataNode = fullData.getChild("data") ?? stanza.getChild("data")
        let dataAttrs = dataNode?.attributes ?? [:]
        // Try both "photo" and "photoURL" attributes
        let photoURL = dataAttrs["photoURL"] ?? dataAttrs["photo"] ?? ""
        
        return MessageData(
            id: finalId,
            body: body,
            roomJid: roomJid,
            date: date,
            userWallet: userWallet,
            photoURL: photoURL,
            dataAttrs: dataAttrs,
            deleted: deleted,
            translations: translations,
            langSource: langSource,
            xmppId: xmppId,
            xmppFrom: xmppFrom
        )
    }

    public static func createMessageFromData(_ d: MessageData) -> Message {
        // Use User and Message from Models (not local definitions)
        let user = User(
            id: d.userWallet,
            name: d.dataAttrs["fullName"] ?? d.userWallet,
            firstName: d.dataAttrs["senderFirstName"],
            lastName: d.dataAttrs["senderLastName"],
            profileImage: d.photoURL,
            xmppUsername: d.userWallet
        )

        // Extract media-related fields from data attributes
        let location = d.dataAttrs["location"]?.isEmpty == false ? d.dataAttrs["location"] : nil
        let locationPreview = d.dataAttrs["locationPreview"]?.isEmpty == false ? d.dataAttrs["locationPreview"] : nil
        var mimetype = d.dataAttrs["mimetype"]?.isEmpty == false ? d.dataAttrs["mimetype"] : nil
        let originalName = d.dataAttrs["originalName"]?.isEmpty == false ? d.dataAttrs["originalName"] : nil
        var fileName = d.dataAttrs["fileName"]?.isEmpty == false ? d.dataAttrs["fileName"] : nil
        let size = d.dataAttrs["size"]?.isEmpty == false ? d.dataAttrs["size"] : nil

        // Fallbacks for media messages: some servers/clients omit `mimetype` or provide an empty string.
        // UI relies on `mimetype` to decide how to render (image/video/audio/file).
        if (d.dataAttrs["isMediafile"] == "true" || d.body == "media") {
            if (mimetype == nil || mimetype?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true) {
                if let loc = location ?? locationPreview {
                    mimetype = inferMimeType(from: loc)
                }
            }
            // If filename is missing or looks like a generic blob, build a nicer name from URL + mimetype.
            if fileName == nil || fileName?.lowercased() == "blob" || fileName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                if let loc = location, let ext = URL(string: loc)?.pathExtension, !ext.isEmpty {
                    fileName = "media.\(ext)"
                } else if let mt = mimetype, let ext = fileExtension(fromMimeType: mt) {
                    fileName = "media.\(ext)"
                }
            }
        }
        
        // Debug logging for media messages
        if d.dataAttrs["isMediafile"] == "true" {
            //print("📎 MessageParser: Parsing media message")
            //print("   location: \(location ?? "nil")")
            //print("   locationPreview: \(locationPreview ?? "nil")")
            //print("   mimetype: \(mimetype ?? "nil")")
            //print("   originalName: \(originalName ?? "nil")")
            //print("   fileName: \(fileName ?? "nil")")
            //print("   size: \(size ?? "nil")")
        }

        // Match TypeScript: createMessageFromXml doesn't filter body, but addRoomMessage does
        // So we create message with body (even if empty), and it will be filtered in handleIncomingMessage
        return Message(
            id: d.id,
            user: user,
            date: d.date,
            body: d.body ?? "", // Empty body will be filtered out in handleIncomingMessage
            roomJid: d.roomJid,
            isSystemMessage: d.dataAttrs["isSystemMessage"],
            isMediafile: d.dataAttrs["isMediafile"],
            locationPreview: locationPreview,
            mimetype: mimetype,
            location: location,
            pending: nil,
            timestamp: Int64(d.date.timeIntervalSince1970 * 1000),
            showInChannel: d.dataAttrs["showInChannel"],
            isReply: d.dataAttrs["isReply"] == "true" || d.dataAttrs["isReply"] == "1",
            isDeleted: d.deleted,
            mainMessage: d.dataAttrs["mainMessage"],
            fileName: fileName,
            translations: convertTranslations(d.translations),
            langSource: d.langSource,
            originalName: originalName,
            size: size,
            xmppId: d.xmppId,
            xmppFrom: d.xmppFrom
        )
    }

    private static func inferMimeType(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic", "heif": return "image/heic"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "m4a": return "audio/m4a"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "pdf": return "application/pdf"
        default: return nil
        }
    }

    private static func fileExtension(fromMimeType mimeType: String) -> String? {
        let mt = mimeType.lowercased()
        if mt == "image/jpeg" { return "jpg" }
        if mt == "image/png" { return "png" }
        if mt == "image/gif" { return "gif" }
        if mt == "image/webp" { return "webp" }
        if mt == "image/heic" { return "heic" }
        if mt == "video/mp4" { return "mp4" }
        if mt == "video/quicktime" { return "mov" }
        if mt == "audio/m4a" { return "m4a" }
        if mt == "audio/mpeg" { return "mp3" }
        if mt == "audio/wav" { return "wav" }
        if mt.contains("pdf") { return "pdf" }
        return nil
    }
    
    // Helper to convert [String: String] to [String: MessageTranslation]
    private static func convertTranslations(_ translations: [String: String]?) -> [String: MessageTranslation]? {
        guard let translations = translations else { return nil }
        return translations.reduce(into: [String: MessageTranslation]()) { result, pair in
            result[pair.key] = MessageTranslation(
                translatedText: pair.value,
                sourceLanguage: nil,
                targetLanguage: pair.key
            )
        }
    }
}
