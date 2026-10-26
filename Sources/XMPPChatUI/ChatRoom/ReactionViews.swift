//
//  ReactionViews.swift
//  XMPPChatUI
//
//  Reaction chips under a bubble, the quick-reaction items and the full
//  emoji picker. Values are shortcodes; the glyph comes from EmojiShortcodes.
//  Mirrors web MessageReaction.tsx (chips, count, my-reaction highlight,
//  long-press names) and EmojiPicker (categories, grid).
//

import SwiftUI
import XMPPChatCore

/// Reaction feature switches, read from the RN-named config keys.
enum ReactionSettings {
    static func enabled(_ config: ChatConfig) -> Bool {
        config.disableReactions != true && config.reactions?.enabled != false
    }

    static func quickShortcodes(_ config: ChatConfig) -> [String] {
        let configured = config.reactions?.quickReactions ?? []
        return configured.isEmpty
            ? EmojiShortcodes.defaultQuickReactions
            : Array(configured.prefix(8))
    }

    static func pickerEnabled(_ config: ChatConfig) -> Bool {
        enabled(config) && config.reactions?.picker != false
    }

    static func repliesEnabled(_ config: ChatConfig) -> Bool {
        config.disableReplies != true
    }
}

/// Chips shown under a bubble: one per shortcode, with the count. The chip the
/// current user reacted with is filled. Tap toggles it; long press lists names.
struct ReactionChipsView: View {
    let reactions: [String: ReactionMessage]?
    let currentReactorKey: String?
    let accentColor: Color
    let interactive: Bool
    let onToggle: (String) -> Void

    private let maxVisible = 6

    var body: some View {
        let summaries = MessageReactions.summaries(reactions)
        if !summaries.isEmpty {
            let visible = Array(summaries.prefix(maxVisible))
            let hidden = summaries.count - visible.count
            HStack(spacing: 4) {
                ForEach(visible, id: \.shortcode) { summary in
                    chip(for: summary)
                }
                if hidden > 0 {
                    Text("+\(hidden)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(Capsule().fill(Color(.systemBackground)))
                        .overlay(Capsule().stroke(Color.gray.opacity(0.25), lineWidth: 1))
                }
            }
        }
    }

    @ViewBuilder
    private func chip(for summary: MessageReactions.Summary) -> some View {
        let mine = currentReactorKey.map { summary.reactorKeys.contains($0) } ?? false
        let glyph = EmojiShortcodes.glyph(for: summary.shortcode) ?? summary.shortcode
        let label = HStack(spacing: 4) {
            Text(glyph).font(.system(size: 14))
            Text("\(summary.count)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundColor(mine ? .white : accentColor)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            Capsule().fill(mine ? accentColor : Color(.systemBackground))
        )
        .overlay(
            Capsule().stroke(Color.gray.opacity(0.25), lineWidth: 1)
        )

        if interactive {
            Button {
                onToggle(summary.shortcode)
            } label: {
                label
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(glyph) \(summary.count)\(mine ? ", you reacted" : "")"))
            .contextMenu {
                // Long press lists who reacted, as the web tooltip does.
                Text("\(summary.reactorNames.joined(separator: ", ")) reacted with \(glyph)")
            }
        } else {
            label
        }
    }
}

/// Quick reactions for the long-press menu: a compact row of the configured
/// shortcodes, plus an entry to open the full picker.
struct ReactionQuickItems: View {
    let shortcodes: [String]
    let showPicker: Bool
    let onSelect: (String) -> Void
    let onMore: () -> Void

    var body: some View {
        ControlGroup {
            ForEach(shortcodes, id: \.self) { shortcode in
                Button {
                    onSelect(shortcode)
                } label: {
                    Text(EmojiShortcodes.glyph(for: shortcode) ?? shortcode)
                }
            }
            if showPicker {
                Button {
                    onMore()
                } label: {
                    Label("More", systemImage: "plus")
                }
            }
        }
    }
}

/// Full emoji picker: category tabs and a grid. Selecting an emoji reports its
/// shortcode and dismisses the sheet.
struct ReactionPickerSheet: View {
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var category: String = EmojiShortcodes.categoryOrder.first ?? "people"

    private let columns = [GridItem(.adaptive(minimum: 40), spacing: 6)]

    var body: some View {
        NavigationView {
            VStack(spacing: 8) {
                Picker("Category", selection: $category) {
                    ForEach(EmojiShortcodes.categoryOrder, id: \.self) { id in
                        Text(Self.title(for: id)).tag(id)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(EmojiShortcodes.entries(in: category), id: \.shortcode) { entry in
                            Button {
                                onSelect(entry.shortcode)
                                dismiss()
                            } label: {
                                Text(entry.glyph)
                                    .font(.system(size: 28))
                                    .frame(width: 40, height: 40)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(entry.shortcode.replacingOccurrences(of: "_", with: " ")))
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.top, 8)
            .navigationTitle("Reactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private static func title(for categoryID: String) -> String {
        switch categoryID {
        case "people": return "People"
        case "nature": return "Nature"
        case "foods": return "Food"
        case "activity": return "Activity"
        case "places": return "Places"
        case "objects": return "Objects"
        case "symbols": return "Symbols"
        case "flags": return "Flags"
        default: return categoryID.capitalized
        }
    }
}
