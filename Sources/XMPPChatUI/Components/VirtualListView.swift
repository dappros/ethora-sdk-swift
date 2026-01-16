//
//  VirtualListView.swift
//  XMPPChatUI
//
//  Virtual scrolling list for performance
//

import SwiftUI

public struct VirtualListView<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let itemHeight: CGFloat
    let visibleRange: Range<Int>
    @ViewBuilder let content: (Item) -> Content
    
    @State private var scrollOffset: CGFloat = 0
    
    public init(
        items: [Item],
        itemHeight: CGFloat = 50,
        visibleRange: Range<Int> = 0..<20,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.items = items
        self.itemHeight = itemHeight
        self.visibleRange = visibleRange
        self.content = content
    }
    
    public var body: some View {
        GeometryReader { geometry in
            let visibleCount = Int(geometry.size.height / itemHeight) + 2
            let startIndex = max(0, Int(scrollOffset / itemHeight))
            let endIndex = min(items.count, startIndex + visibleCount)
            
            ScrollView {
                VStack(spacing: 0) {
                    // Spacer for items above viewport
                    if startIndex > 0 {
                        Spacer()
                            .frame(height: CGFloat(startIndex) * itemHeight)
                    }
                    
                    // Visible items
                    ForEach(Array(items[startIndex..<endIndex].enumerated()), id: \.element.id) { index, item in
                        content(item)
                            .frame(height: itemHeight)
                    }
                    
                    // Spacer for items below viewport
                    if endIndex < items.count {
                        Spacer()
                            .frame(height: CGFloat(items.count - endIndex) * itemHeight)
                    }
                }
            }
            .background(
                GeometryReader { scrollGeometry in
                    Color.clear
                        .preference(key: ScrollOffsetKey.self, value: scrollGeometry.frame(in: .named("scroll")).minY)
                }
            )
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetKey.self) { value in
                scrollOffset = -value
            }
        }
    }
}

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
