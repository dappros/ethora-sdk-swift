//
//  CallKitPushRegistry.swift
//  XMPPChatCore
//
//  PushKit helper for the CallKit bridge. Registers for VoIP pushes, hands the
//  device token to the SDK's push registration (`apns-voip` slot) and routes
//  every VoIP push to CallKitBridge. A host that already owns a PKPushRegistry
//  skips this class and calls `CallKitBridge.shared.handleVoIPPush` from its own
//  delegate instead.
//

#if canImport(PushKit) && canImport(CallKit)
import Foundation
import PushKit

@MainActor
public final class CallKitPushRegistry: NSObject {
    public static let shared = CallKitPushRegistry()

    private var registry: PKPushRegistry?

    /// Receives the VoIP device token as a hex string (after the SDK registered
    /// it, when `registersTokenWithSDK` is true).
    public var onVoIPToken: ((String) -> Void)?
    /// Register the token with the Ethora backend automatically. Default true.
    public var registersTokenWithSDK = true

    private override init() { super.init() }

    /// Starts listening for VoIP pushes. Call at launch, after
    /// `CallKitBridge.shared.enable`.
    public func register(queue: DispatchQueue = .main) {
        guard registry == nil else { return }
        let registry = PKPushRegistry(queue: queue)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        self.registry = registry
    }

    public func unregister() {
        registry?.desiredPushTypes = []
        registry = nil
    }

    /// Hex form of a PushKit token.
    nonisolated static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

/// Carries a push payload and its completion across the queue hop.
private final class PushPayloadBox: @unchecked Sendable {
    let payload: [AnyHashable: Any]
    let completion: () -> Void

    init(payload: [AnyHashable: Any], completion: @escaping () -> Void) {
        self.payload = payload
        self.completion = completion
    }

    func deliverOnMain() {
        MainActor.assumeIsolated {
            _ = CallKitBridge.shared.handleVoIPPush(payload, completion: completion)
        }
    }
}

extension CallKitPushRegistry: PKPushRegistryDelegate {
    nonisolated public func pushRegistry(
        _ registry: PKPushRegistry,
        didUpdate pushCredentials: PKPushCredentials,
        for type: PKPushType
    ) {
        guard type == .voIP else { return }
        let token = Self.hex(pushCredentials.token)
        Task { @MainActor in
            if self.registersTokenWithSDK {
                _ = try? await PushNotificationManager.shared.registerPushToken(token, tokenType: .apnsVoip)
            }
            self.onVoIPToken?(token)
        }
    }

    nonisolated public func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        guard type == .voIP else { completion(); return }
        // iOS wants the CallKit report inside this callback. The registry queue is
        // the main queue by default, so assume main-actor isolation; on any other
        // queue hop to main (the report is then slightly later).
        let box = PushPayloadBox(payload: payload.dictionaryPayload, completion: completion)
        if Thread.isMainThread {
            box.deliverOnMain()
        } else {
            DispatchQueue.main.async { box.deliverOnMain() }
        }
    }

    nonisolated public func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        Task { @MainActor in
            try? await PushNotificationManager.shared.unregisterPushToken(tokenType: .apnsVoip)
        }
    }
}
#endif
