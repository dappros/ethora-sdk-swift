//
//  ErrorBoundary.swift
//  XMPPChatUI
//
//  Error boundary component
//

import SwiftUI

public struct ErrorBoundary<Content: View>: View {
    let content: Content
    let fallback: (Error) -> AnyView
    
    @State private var error: Error?
    
    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder fallback: @escaping (Error) -> AnyView
    ) {
        self.content = content()
        self.fallback = fallback
    }
    
    public var body: some View {
        Group {
            if let error = error {
                fallback(error)
            } else {
                content
                    .onAppear {
                        // Reset error when view appears
                        error = nil
                    }
            }
        }
    }
    
    public func catchError(_ error: Error) {
        self.error = error
    }
}

public struct ErrorFallbackView: View {
    let error: Error
    let onRetry: (() -> Void)?
    
    public init(error: Error, onRetry: (() -> Void)? = nil) {
        self.error = error
        self.onRetry = onRetry
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Something went wrong")
                .font(.headline)
            
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if let onRetry = onRetry {
                Button("Retry", action: onRetry)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
