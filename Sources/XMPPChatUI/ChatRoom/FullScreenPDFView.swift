//
//  FullScreenPDFView.swift
//  XMPPChatUI
//

import SwiftUI

struct FullScreenPDFView: View {
    let pdfURL: URL
    let fileName: String
    let onClose: () -> Void
    
    var body: some View {
        NavigationView {
            #if os(iOS)
            PDFViewer(url: pdfURL)
                .navigationTitle(fileName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Close") {
                            onClose()
                        }
                    }
                }
            #else
            Text("PDF Viewer not available on macOS")
            #endif
        }
    }
}
