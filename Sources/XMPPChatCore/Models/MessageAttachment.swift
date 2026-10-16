//
//  MessageAttachment.swift
//  XMPPChatCore
//
//  One file of a media message. Translated from types/models/attachment.model.ts and helpers/attachments.ts
//

import Foundation

/// One uploaded file carried by a media message.
///
/// A media message describes its first file through the flat `<data>` attributes (`location`, `mimetype`, ...),
/// and the whole set through the `attachments` JSON attribute when there is more than one file. Older clients
/// keep reading the flat fields and see attachment #0 only.
public struct MessageAttachment: Codable, Equatable, Hashable {
    /// `_id` returned by the upload endpoint. Stable per upload.
    public var attachmentId: String?
    /// Canonical file URL.
    public var location: String
    /// Server-side preview, images always and other types sometimes.
    public var locationPreview: String?
    public var mimetype: String?
    /// Name the sender picked.
    public var originalName: String?
    /// Name on the storage side.
    public var fileName: String?
    /// Size in bytes, as a string (that is how it travels on the wire).
    public var size: String?
    public var duration: String?

    public init(
        attachmentId: String? = nil,
        location: String,
        locationPreview: String? = nil,
        mimetype: String? = nil,
        originalName: String? = nil,
        fileName: String? = nil,
        size: String? = nil,
        duration: String? = nil
    ) {
        self.attachmentId = attachmentId
        self.location = location
        self.locationPreview = locationPreview
        self.mimetype = mimetype
        self.originalName = originalName
        self.fileName = fileName
        self.size = size
        self.duration = duration
    }

    /// Name to show: the original name, then the stored name, then the URL tail.
    public var displayName: String {
        if let originalName = originalName, !originalName.isEmpty { return originalName }
        if let fileName = fileName, !fileName.isEmpty { return fileName }
        if let tail = URL(string: location)?.lastPathComponent, !tail.isEmpty { return tail }
        return "MediaFile"
    }

    /// Coarse kind from the mimetype, falling back to the name's extension.
    public var isImage: Bool { effectiveMimetype.hasPrefix("image/") }
    public var isVideo: Bool { effectiveMimetype.hasPrefix("video/") }
    public var isAudio: Bool { effectiveMimetype.hasPrefix("audio/") }
    public var isPDF: Bool { effectiveMimetype.contains("pdf") }

    /// The mimetype, or one inferred from the names when the sender left it generic or empty.
    public var effectiveMimetype: String {
        MessageAttachments.resolveMimetype(
            mimetype,
            names: [originalName, fileName, location]
        ) ?? "application/octet-stream"
    }
}

/// Reading and writing the multi-file wire form. Pure functions, no XMPP or UI.
public enum MessageAttachments {
    /// Hard ceiling on how many attachments one message may carry, also enforced on receive.
    public static let maxPerMessage = 10

    /// Parses the `attachments` data attribute (a JSON array). Accepts the camelCase and the API's own spelling
    /// (`originalname`, `filename`) and numeric or string sizes. Entries without a location are dropped.
    /// Never throws; junk yields an empty array.
    public static func parse(_ raw: String?) -> [MessageAttachment] {
        guard let raw = raw, !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            return []
        }
        return array
            .prefix(maxPerMessage)
            .compactMap { item -> MessageAttachment? in
                guard let object = item as? [String: Any] else { return nil }
                let location = string(object["location"]) ?? ""
                guard !location.isEmpty else { return nil }
                let mimetype = string(object["mimetype"])
                return MessageAttachment(
                    attachmentId: string(object["attachmentId"]) ?? string(object["_id"]),
                    location: location,
                    locationPreview: string(object["locationPreview"]),
                    mimetype: resolveMimetype(mimetype, names: [
                        string(object["originalName"]) ?? string(object["originalname"]),
                        string(object["fileName"]) ?? string(object["filename"]),
                        location
                    ]) ?? mimetype,
                    originalName: string(object["originalName"]) ?? string(object["originalname"]),
                    fileName: string(object["fileName"]) ?? string(object["filename"]),
                    size: string(object["size"]),
                    duration: string(object["duration"]) ?? string(object["mediaDuration"])
                )
            }
    }

    /// The wire form for the `attachments` attribute: at most `maxPerMessage` entries, only the fields a receiver
    /// renders.
    public static func serialize(_ attachments: [MessageAttachment]) -> String {
        let items: [[String: String]] = attachments.prefix(maxPerMessage).map { attachment in
            var object: [String: String] = ["location": attachment.location]
            if let value = attachment.attachmentId { object["attachmentId"] = value }
            if let value = attachment.locationPreview { object["locationPreview"] = value }
            if let value = attachment.mimetype { object["mimetype"] = value }
            if let value = attachment.originalName { object["originalName"] = value }
            if let value = attachment.fileName { object["fileName"] = value }
            if let value = attachment.size { object["size"] = value }
            if let value = attachment.duration { object["duration"] = value }
            return object
        }
        guard let data = try? JSONSerialization.data(withJSONObject: items, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }

    /// Files described by the flat legacy fields. A comma separated list of URLs is several files, the other
    /// flat fields then hold one value each in the same order, or one value for all of them.
    public static func fromLegacyFields(
        location: String?,
        locationPreview: String? = nil,
        mimetype: String? = nil,
        originalName: String? = nil,
        fileName: String? = nil,
        size: String? = nil,
        duration: String? = nil
    ) -> [MessageAttachment] {
        let locations = splitURLList(location)
        if locations.count > 1 {
            let previews = splitURLList(locationPreview)
            let mimetypes = splitList(mimetype)
            let names = splitList(originalName)
            return locations.prefix(maxPerMessage).enumerated().map { index, url in
                MessageAttachment(
                    location: url,
                    locationPreview: previews.count == locations.count ? previews[index] : nil,
                    mimetype: pickNth(mimetypes, index, locations.count),
                    originalName: pickNth(names, index, locations.count)
                )
            }
        }
        guard let single = locations.first else { return [] }
        return [MessageAttachment(
            location: single,
            locationPreview: nonEmpty(locationPreview),
            mimetype: nonEmpty(mimetype),
            originalName: nonEmpty(originalName),
            fileName: nonEmpty(fileName),
            size: nonEmpty(size),
            duration: nonEmpty(duration)
        )]
    }

    /// The file a successful upload describes. Nil when the response lacks a location.
    public static func fromUpload(_ result: UploadResult) -> MessageAttachment? {
        guard let location = result.location, !location.isEmpty else { return nil }
        return MessageAttachment(
            attachmentId: result._id,
            location: location,
            locationPreview: result.locationPreview,
            mimetype: result.mimetype,
            originalName: result.originalname ?? result.filename,
            fileName: result.filename,
            size: result.size.map { String($0) },
            duration: result.duration
        )
    }

    /// The mimetype a file should be shown as. A generic or missing type is replaced by one inferred from the
    /// first name with a known extension. Nil when nothing is known.
    public static func resolveMimetype(_ mimetype: String?, names: [String?]) -> String? {
        let trimmed = mimetype?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isGeneric = trimmed.isEmpty || trimmed == "application/octet-stream"
        if !isGeneric { return trimmed }
        for name in names {
            if let inferred = inferMimetype(fromName: name) { return inferred }
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Mimetype from the extension of a name or URL path. Nil for unknown extensions.
    public static func inferMimetype(fromName name: String?) -> String? {
        guard let name = name, !name.isEmpty else { return nil }
        let path = name.split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) ?? name
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "heif": return "image/heif"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "m4a": return "audio/mp4"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "aac": return "audio/aac"
        case "pdf": return "application/pdf"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls": return "application/vnd.ms-excel"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "txt": return "text/plain"
        default: return nil
        }
    }

    // MARK: - Helpers

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String:
            return text.isEmpty ? nil : text
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value, !value.isEmpty else { return nil }
        return value
    }

    private static func splitURLList(_ value: String?) -> [String] {
        guard let value = value, !value.isEmpty else { return [] }
        let pattern = ",\\s*(?=https?://)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil else {
            return [value]
        }
        let range = NSRange(value.startIndex..., in: value)
        var parts: [String] = []
        var cursor = value.startIndex
        for match in regex.matches(in: value, range: range) {
            guard let matchRange = Range(match.range, in: value) else { continue }
            parts.append(String(value[cursor..<matchRange.lowerBound]))
            cursor = matchRange.upperBound
        }
        parts.append(String(value[cursor...]))
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func splitList(_ value: String?) -> [String] {
        guard let value = value, !value.isEmpty else { return [] }
        return value.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func pickNth(_ list: [String], _ index: Int, _ total: Int) -> String? {
        if list.count == total { return nonEmpty(list[index]) }
        if list.count == 1 { return nonEmpty(list[0]) }
        return nil
    }
}

extension Message {
    /// Every file this media message carries, in order. Reads the `attachments` payload when present, otherwise
    /// the flat legacy fields. Use this, not the flat fields, to render a media message.
    public var mediaAttachments: [MessageAttachment] {
        if let attachments = attachments, !attachments.isEmpty {
            return Array(attachments.prefix(MessageAttachments.maxPerMessage))
        }
        return MessageAttachments.fromLegacyFields(
            location: location,
            locationPreview: locationPreview,
            mimetype: mimetype,
            originalName: originalName,
            fileName: fileName,
            size: size
        )
    }
}
