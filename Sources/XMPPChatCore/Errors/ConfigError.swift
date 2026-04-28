//
//  ConfigError.swift
//  XMPPChatCore
//
//  Errors thrown when the host application starts the SDK without
//  filling in `ChatConfig` with their own backend endpoints. The SDK
//  intentionally ships without hardcoded defaults — the host MUST
//  configure `baseUrl`, `xmppSettings`, and `appId` via
//  `ConfigStore.shared.mergeConfig(_:)` before mounting chat or
//  starting `ChatHeadlessSession`.
//

import Foundation

public enum ConfigError: Error, LocalizedError, Equatable {
    case missingBaseURL
    case missingXMPPSettings
    case missingAppId
    case invalidBaseURL(String)

    public var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "ChatConfig.baseUrl is not set. Call ConfigStore.shared.mergeConfig with a non-empty baseUrl before connecting."
        case .missingXMPPSettings:
            return "ChatConfig.xmppSettings is not set. Provide host/conference/devServer via ConfigStore.shared.mergeConfig before connecting."
        case .missingAppId:
            return "ChatConfig.appId is not set. Provide your application id via ConfigStore.shared.mergeConfig before connecting."
        case .invalidBaseURL(let raw):
            return "ChatConfig.baseUrl is not a valid URL: \(raw)"
        }
    }
}
