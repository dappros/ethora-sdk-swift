//
//  AttachmentAlbumView.swift
//  XMPPChatUI
//
//  Photo/file album for a message with several files. Layout rules follow web helpers/albumLayout.ts.
//

import SwiftUI
import XMPPChatCore

/// Geometry for an album bubble. Pure, so the rules can be tested without a view.
///
///   2 items  side by side
///   3 items  one large tile on the left, two stacked on the right
///   4 items  2 x 2
///   5+ items 2 x 2 showing the first four, the last tile carries "+N"
enum AttachmentAlbumLayout {
    enum Kind: Equatable { case pair, hero, quad }

    struct Result: Equatable {
        let kind: Kind
        /// Number of tiles drawn.
        let visible: Int
        /// Files folded into the "+N" overlay on the last visible tile.
        let hidden: Int
    }

    /// Layout for `count` files. Counts below 2 are not albums; they are treated as a pair.
    static func make(count: Int) -> Result {
        let total = max(2, count)
        switch total {
        case 2:
            return Result(kind: .pair, visible: 2, hidden: 0)
        case 3:
            return Result(kind: .hero, visible: 3, hidden: 0)
        default:
            return Result(kind: .quad, visible: 4, hidden: total - 4)
        }
    }
}

struct AttachmentAlbumView: View {
    let attachments: [MessageAttachment]
    /// Called with the index of the tapped file in `attachments`.
    let onTap: (Int) -> Void

    private let gap: CGFloat = 3

    var body: some View {
        let layout = AttachmentAlbumLayout.make(count: attachments.count)
        Group {
            switch layout.kind {
            case .pair:
                HStack(spacing: gap) {
                    tile(0, layout: layout)
                    tile(1, layout: layout)
                }
                .aspectRatio(2, contentMode: .fit)
            case .hero:
                HStack(spacing: gap) {
                    tile(0, layout: layout)
                    VStack(spacing: gap) {
                        tile(1, layout: layout)
                        tile(2, layout: layout)
                    }
                }
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
            case .quad:
                VStack(spacing: gap) {
                    HStack(spacing: gap) {
                        tile(0, layout: layout)
                        tile(1, layout: layout)
                    }
                    HStack(spacing: gap) {
                        tile(2, layout: layout)
                        tile(3, layout: layout)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
            }
        }
        .frame(maxWidth: 250)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func tile(_ position: Int, layout: AttachmentAlbumLayout.Result) -> some View {
        let item = attachments[position]
        let isLast = position == layout.visible - 1
        Button(action: { onTap(position) }) {
            ZStack {
                Color.gray.opacity(0.12)
                if item.isImage, let url = SecureFileURL.currentURL(item.locationPreview ?? item.location) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            Image(systemName: "photo").foregroundColor(.gray)
                        default:
                            ProgressView()
                        }
                    }
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: item.isVideo ? "play.circle.fill" : "doc.fill")
                            .font(.title)
                            .foregroundColor(.blue)
                        Text(item.displayName)
                            .font(.caption2)
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                    }
                }
                if isLast && layout.hidden > 0 {
                    Color.black.opacity(0.35)
                    Text("+\(layout.hidden)")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.white)
                }
            }
            .clipped()
        }
        .buttonStyle(PlainButtonStyle())
    }
}
