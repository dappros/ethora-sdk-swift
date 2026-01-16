//
//  ToastView.swift
//  XMPPChatUI
//
//  Toast notification component
//

import SwiftUI

public struct ToastView: View {
    let message: String
    let type: ToastType
    let duration: TimeInterval
    
    @State private var isVisible: Bool = false
    
    public init(
        message: String,
        type: ToastType = .info,
        duration: TimeInterval = 3.0
    ) {
        self.message = message
        self.type = type
        self.duration = duration
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundColor(.white)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(backgroundColor)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
        .offset(y: isVisible ? 0 : -100)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isVisible = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isVisible = false
                }
            }
        }
    }
    
    private var iconName: String {
        switch type {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
    
    private var backgroundColor: Color {
        switch type {
        case .success: return .green
        case .error: return .red
        case .info: return .blue
        case .warning: return .orange
        }
    }
}

public enum ToastType {
    case success
    case error
    case info
    case warning
}

// MARK: - Toast Manager
@MainActor
public class ToastManager: ObservableObject {
    @Published var toasts: [ToastItem] = []
    
    public func show(_ message: String, type: ToastType = .info, duration: TimeInterval = 3.0) {
        let toast = ToastItem(message: message, type: type, duration: duration)
        toasts.append(toast)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            self.toasts.removeAll { $0.id == toast.id }
        }
    }
    
    public func showSuccess(_ message: String) {
        show(message, type: .success)
    }
    
    public func showError(_ message: String) {
        show(message, type: .error)
    }
    
    public func showInfo(_ message: String) {
        show(message, type: .info)
    }
    
    public func showWarning(_ message: String) {
        show(message, type: .warning)
    }
}

struct ToastItem: Identifiable {
    let id = UUID()
    let message: String
    let type: ToastType
    let duration: TimeInterval
}

// MARK: - Toast Container
public struct ToastContainer: View {
    @ObservedObject var manager: ToastManager
    
    public init(manager: ToastManager) {
        self.manager = manager
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            ForEach(manager.toasts) { toast in
                ToastView(
                    message: toast.message,
                    type: toast.type,
                    duration: toast.duration
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
