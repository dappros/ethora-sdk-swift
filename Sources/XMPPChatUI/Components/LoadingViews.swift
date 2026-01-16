//
//  LoadingViews.swift
//  XMPPChatUI
//
//  Loading state views
//

import SwiftUI

public struct SkeletonLoader: View {
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat
    
    public init(width: CGFloat? = nil, height: CGFloat = 20, cornerRadius: CGFloat = 8) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }
    
    public var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: width, height: height)
            .cornerRadius(cornerRadius)
            .shimmer()
    }
}

public struct MessageSendingIndicator: View {
    public var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.blue)
                .frame(width: 8, height: 8)
                .scaleEffect(1.0)
                .animation(
                    Animation.easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true),
                    value: UUID()
                )
            
            Circle()
                .fill(Color.blue)
                .frame(width: 8, height: 8)
                .scaleEffect(1.0)
                .animation(
                    Animation.easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true)
                        .delay(0.2),
                    value: UUID()
                )
            
            Circle()
                .fill(Color.blue)
                .frame(width: 8, height: 8)
                .scaleEffect(1.0)
                .animation(
                    Animation.easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true)
                        .delay(0.4),
                    value: UUID()
                )
        }
        .padding(.horizontal, 8)
    }
}

public struct MediaUploadProgress: View {
    let progress: Double
    
    public init(progress: Double) {
        self.progress = progress
    }
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: geometry.size.width * CGFloat(progress))
                    .animation(.linear, value: progress)
            }
            .cornerRadius(4)
        }
        .frame(height: 4)
    }
}

extension View {
    func shimmer() -> some View {
        self.modifier(ShimmerModifier())
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.5),
                        Color.white.opacity(0)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .animation(
                    Animation.linear(duration: 1.5)
                        .repeatForever(autoreverses: false),
                    value: phase
                )
            )
            .onAppear {
                phase = 300
            }
    }
}
