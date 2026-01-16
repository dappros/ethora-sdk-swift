//
//  KeyboardHandler.swift
//  XMPPChatUI
//
//  Keyboard handling for chat input
//

import SwiftUI
import Combine

#if os(iOS)
public class KeyboardHandler: ObservableObject {
    @Published public var keyboardHeight: CGFloat = 0
    @Published public var isKeyboardVisible: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { [weak self] notification in
                if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    self?.keyboardHeight = keyboardFrame.height
                    self?.isKeyboardVisible = true
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] _ in
                self?.keyboardHeight = 0
                self?.isKeyboardVisible = false
            }
            .store(in: &cancellables)
    }
    
    public func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

extension View {
    public func keyboardAware() -> some View {
        self.modifier(KeyboardAwareModifier())
    }
}

struct KeyboardAwareModifier: ViewModifier {
    @StateObject private var keyboardHandler = KeyboardHandler()
    
    func body(content: Content) -> some View {
        content
            .padding(.bottom, keyboardHandler.keyboardHeight)
            .animation(.easeInOut(duration: 0.3), value: keyboardHandler.keyboardHeight)
    }
}
#else
public class KeyboardHandler: ObservableObject {
    @Published public var keyboardHeight: CGFloat = 0
    @Published public var isKeyboardVisible: Bool = false
    
    public init() {}
    public func dismissKeyboard() {}
}

extension View {
    public func keyboardAware() -> some View {
        self
    }
}
#endif
