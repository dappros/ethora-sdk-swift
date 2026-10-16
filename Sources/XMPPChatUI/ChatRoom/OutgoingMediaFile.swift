//
//  OutgoingMediaFile.swift
//  XMPPChatUI
//
//  One file the composer hands to the view model, before upload.
//

import Foundation

public struct OutgoingMediaFile: Equatable {
    public let data: Data
    /// MIME type the picker reported (`image/jpeg`, `video/mp4`, `application/pdf`, ...).
    public let mimeType: String
    /// Name the user picked, for documents. Nil for photos and camera captures, which get a generated name.
    public let fileName: String?

    public init(data: Data, mimeType: String, fileName: String? = nil) {
        self.data = data
        self.mimeType = mimeType
        self.fileName = fileName
    }
}
