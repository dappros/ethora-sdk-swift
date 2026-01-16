//
//  PDFViewer.swift
//  XMPPChatUI
//
//  Enhanced PDF viewer with navigation
//

import SwiftUI
import PDFKit

#if os(iOS)
public struct PDFViewer: UIViewRepresentable {
    let url: URL
    
    public init(url: URL) {
        self.url = url
    }
    
    public func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        
        if let document = PDFDocument(url: url) {
            pdfView.document = document
        }
        
        return pdfView
    }
    
    public func updateUIView(_ pdfView: PDFView, context: Context) {
        // No updates needed
    }
}

public struct PDFViewerWithControls: View {
    let url: URL
    @State private var pdfView: PDFView?
    @State private var currentPage: Int = 0
    @State private var totalPages: Int = 0
    
    public init(url: URL) {
        self.url = url
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // PDF View
            PDFViewer(url: url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Controls
            HStack {
                Button(action: {
                    pdfView?.goToPreviousPage(nil)
                }) {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }
                .disabled(currentPage <= 0)
                
                Text("\(currentPage + 1) / \(totalPages)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button(action: {
                    pdfView?.goToNextPage(nil)
                }) {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                }
                .disabled(currentPage >= totalPages - 1)
                
                Spacer()
                
                Button(action: {
                    // Download
                }) {
                    Image(systemName: "arrow.down.circle")
                        .font(.title3)
                }
                
                Button(action: {
                    // Share
                }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                }
            }
            .padding()
            .background(Color(.systemBackground))
        }
    }
}
#endif
