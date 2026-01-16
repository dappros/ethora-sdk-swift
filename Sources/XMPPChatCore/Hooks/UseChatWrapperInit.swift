//
//  UseChatWrapperInit.swift
//  XMPPChatCore
//
//  Chat wrapper initialization
//

import Foundation
import Combine

@MainActor
public class ChatWrapperInit: ObservableObject {
    @Published public var isInitialized: Bool = false
    @Published public var initializationError: Error?
    
    private var cancellables = Set<AnyCancellable>()
    
    public func initialize(
        config: ChatConfig,
        client: XMPPClient?,
        onComplete: @escaping () -> Void
    ) {
        Task {
            do {
                // Initialize XMPP client if needed
                if let client = client {
                    // Setup client
                }
                
                // Load initial data
                // Load rooms, messages, etc.
                
                await MainActor.run {
                    isInitialized = true
                    onComplete()
                }
            } catch {
                await MainActor.run {
                    initializationError = error
                }
            }
        }
    }
    
    public func reset() {
        isInitialized = false
        initializationError = nil
    }
}
