//
//  FullScreenPDFView.swift
//  XMPPChatUI
//

import SwiftUI
#if os(iOS)
import PDFKit
#endif

struct FullScreenPDFView: View {
    let pdfURL: URL
    let fileName: String
    let onClose: () -> Void

    #if os(iOS)
    @State private var document: PDFDocument? = nil
    @State private var loadError: String? = nil
    #endif

    var body: some View {
        NavigationView {
            #if os(iOS)
            Group {
                if let document = document {
                    PDFKitView(document: document)
                } else if let loadError = loadError {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("Failed to open document")
                            .font(.headline)
                        Text(loadError)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { onClose() }
                }
            }
            .task { await loadDocument() }
            #else
            Text("PDF Viewer is available on iOS only")
            #endif
        }
    }

    #if os(iOS)
    private func loadDocument() async {
        // PDFKit's PDFDocument(url:) blocks on remote URLs. Download the bytes
        // ourselves on a background task and build the document from Data —
        // keeps the UI responsive and gives us a real error message if the
        // download fails.
        do {
            let (data, _) = try await URLSession.shared.data(from: pdfURL)
            if let doc = PDFDocument(data: data) {
                await MainActor.run { self.document = doc }
            } else {
                await MainActor.run { self.loadError = "Not a valid PDF file" }
            }
        } catch {
            await MainActor.run { self.loadError = error.localizedDescription }
        }
    }

    private struct PDFKitView: UIViewRepresentable {
        let document: PDFDocument
        func makeUIView(context: Context) -> PDFView {
            let view = PDFView()
            view.autoScales = true
            view.displayMode = .singlePageContinuous
            view.displayDirection = .vertical
            view.document = document
            return view
        }
        func updateUIView(_ view: PDFView, context: Context) {
            if view.document !== document { view.document = document }
        }
    }
    #endif
}
