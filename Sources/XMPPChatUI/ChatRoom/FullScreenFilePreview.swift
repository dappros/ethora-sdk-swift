//
//  FullScreenFilePreview.swift
//  XMPPChatUI
//
//  Универсальный превьюер для файлов, которые не являются image/video/pdf:
//  аудио, документы, архивы и т.п. Использует QuickLook — нативный системный
//  просмотрщик iOS, который сам умеет рендерить всё что поддерживает Files.
//

import SwiftUI
#if os(iOS)
import UIKit
import QuickLook
#endif

struct FullScreenFilePreview: View {
    let fileURL: URL
    let fileName: String
    let onClose: () -> Void

    #if os(iOS)
    @State private var localURL: URL? = nil
    @State private var loadError: String? = nil
    #endif

    var body: some View {
        #if os(iOS)
        NavigationView {
            Group {
                if let localURL = localURL {
                    QuickLookView(url: localURL)
                } else if let loadError = loadError {
                    VStack(spacing: 12) {
                        Image(systemName: "doc")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("Failed to open file")
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
            .task { await downloadFile() }
        }
        #else
        Text("File preview is available on iOS only")
        #endif
    }

    #if os(iOS)
    private func downloadFile() async {
        // QuickLook умеет только с локальными URL. Скачиваем в temp и передаём.
        // Имя файла сохраняем как в исходнике, чтобы Quick Look корректно
        // определил UTI по расширению.
        do {
            let (data, _) = try await URLSession.shared.data(from: fileURL)
            let safeName = fileName.isEmpty ? "file" : fileName
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent(safeName)
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: dest)
            await MainActor.run { self.localURL = dest }
        } catch {
            await MainActor.run { self.loadError = error.localizedDescription }
        }
    }

    private struct QuickLookView: UIViewControllerRepresentable {
        let url: URL

        func makeCoordinator() -> Coordinator { Coordinator(url: url) }

        func makeUIViewController(context: Context) -> QLPreviewController {
            let vc = QLPreviewController()
            vc.dataSource = context.coordinator
            return vc
        }

        func updateUIViewController(_ vc: QLPreviewController, context: Context) {
            context.coordinator.url = url
            vc.reloadData()
        }

        final class Coordinator: NSObject, QLPreviewControllerDataSource {
            var url: URL
            init(url: URL) { self.url = url }
            func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
            func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
                url as QLPreviewItem
            }
        }
    }
    #endif
}
