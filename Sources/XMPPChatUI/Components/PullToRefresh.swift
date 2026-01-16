//
//  PullToRefresh.swift
//  XMPPChatUI
//
//  Pull to refresh component
//

import SwiftUI

public struct PullToRefresh: ViewModifier {
    let onRefresh: () async -> Void
    @State private var isRefreshing = false
    @State private var offset: CGFloat = 0
    @State private var startOffset: CGFloat = 0
    
    public func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: ScrollOffsetPreferenceKey.self, value: geometry.frame(in: .named("scroll")).minY)
                }
            )
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                if startOffset == 0 {
                    startOffset = value
                }
                offset = value - startOffset
                
                if offset > 80 && !isRefreshing {
                    isRefreshing = true
                    Task {
                        await onRefresh()
                        await MainActor.run {
                            isRefreshing = false
                            startOffset = 0
                        }
                    }
                }
            }
            .overlay(
                Group {
                    if isRefreshing {
                        ProgressView()
                            .offset(y: -30)
                    }
                },
                alignment: .top
            )
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    public func pullToRefresh(onRefresh: @escaping () async -> Void) -> some View {
        self.modifier(PullToRefresh(onRefresh: onRefresh))
    }
}
