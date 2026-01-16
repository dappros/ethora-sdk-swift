//
//  UseTabVisibility.swift
//  XMPPChatCore
//
//  Tab visibility handling
//

import Foundation
import Combine

#if os(iOS)
import UIKit

@MainActor
public class TabVisibilityManager: ObservableObject {
    @Published public var isVisible: Bool = true
    
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        setupObservers()
    }
    
    private func setupObservers() {
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.isVisible = false
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.isVisible = true
            }
            .store(in: &cancellables)
    }
}
#else
@MainActor
public class TabVisibilityManager: ObservableObject {
    @Published public var isVisible: Bool = true
    public init() {}
}
#endif
