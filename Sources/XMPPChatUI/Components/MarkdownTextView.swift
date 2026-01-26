//
//  MarkdownTextView.swift
//  XMPPChatUI
//
//  Markdown text rendering component
//

import SwiftUI

/// A view that renders markdown text with proper formatting
@available(iOS 15.0, macOS 12.0, *)
public struct MarkdownTextView: View {
    let text: String
    let foregroundColor: Color
    
    public init(text: String, foregroundColor: Color = .primary) {
        self.text = text
        self.foregroundColor = foregroundColor
    }
    
    @ViewBuilder
    public var body: some View {
        if let attributedString = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            // Render markdown with color applied via Text modifier
            // This preserves markdown formatting (bold, italic, links) while applying base color
            Text(attributedString)
                .foregroundColor(foregroundColor)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            // Fallback to plain text if markdown parsing fails
            Text(text)
                .foregroundColor(foregroundColor)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Fallback for older iOS versions
@available(iOS, deprecated: 15.0, message: "Use MarkdownTextView instead")
public struct PlainTextView: View {
    let text: String
    let foregroundColor: Color
    
    public init(text: String, foregroundColor: Color = .primary) {
        self.text = text
        self.foregroundColor = foregroundColor
    }
    
    public var body: some View {
        Text(text)
            .foregroundColor(foregroundColor)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Universal markdown text view that works on all iOS versions
public struct UniversalMarkdownTextView: View {
    let text: String
    let foregroundColor: Color
    
    public init(text: String, foregroundColor: Color = .primary) {
        self.text = text
        self.foregroundColor = foregroundColor
    }
    
    public var body: some View {
        if #available(iOS 15.0, macOS 12.0, *) {
            MarkdownTextView(text: text, foregroundColor: foregroundColor)
        } else {
            PlainTextView(text: text, foregroundColor: foregroundColor)
        }
    }
}
