//
//  MediaPickerViews.swift
//  XMPPChatUI
//

import SwiftUI
#if os(iOS)
import PhotosUI
import UniformTypeIdentifiers

struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let mediaTypes: [String]
    var selectionLimit = 1
    let onMediaSelected: (Data, String) -> Void
    /// When set, a multi-select result is delivered once, in the order picked.
    var onBatchSelected: (([(Data, String)]) -> Void)?
    
    func makeUIViewController(context: Context) -> UIViewController {
        if sourceType == .camera {
            let picker = UIImagePickerController()
            picker.sourceType = sourceType
            picker.mediaTypes = mediaTypes
            picker.delegate = context.coordinator
            return picker
        } else {
            var configuration = PHPickerConfiguration()
            
            if mediaTypes.contains("public.image") && mediaTypes.contains("public.movie") {
                configuration.filter = .any(of: [.images, .videos])
            } else if mediaTypes.contains("public.image") {
                configuration.filter = .images
            } else if mediaTypes.contains("public.movie") {
                configuration.filter = .videos
            }
            
            configuration.selectionLimit = max(1, selectionLimit)
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = context.coordinator
            return picker
        }
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onMediaSelected: onMediaSelected, onBatchSelected: onBatchSelected)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onMediaSelected: (Data, String) -> Void
        let onBatchSelected: (([(Data, String)]) -> Void)?
        
        init(onMediaSelected: @escaping (Data, String) -> Void, onBatchSelected: (([(Data, String)]) -> Void)?) {
            self.onMediaSelected = onMediaSelected
            self.onBatchSelected = onBatchSelected
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            if let onBatchSelected {
                loadBatch(results, completion: onBatchSelected)
                return
            }
            guard let result = results.first else { return }
            
            if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                    guard let data = data, error == nil else { return }
                    DispatchQueue.main.async {
                        self.onMediaSelected(data, "image/jpeg")
                    }
                }
            } else if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.movie.identifier) { data, error in
                    guard let data = data, error == nil else { return }
                    DispatchQueue.main.async {
                        self.onMediaSelected(data, "video/mp4")
                    }
                }
            }
        }
        
        /// Loads every picked item and hands them over together, in the order picked.
        private func loadBatch(_ results: [PHPickerResult], completion: @escaping ([(Data, String)]) -> Void) {
            var loaded = [(Data, String)?](repeating: nil, count: results.count)
            let group = DispatchGroup()
            for (index, result) in results.enumerated() {
                let provider = result.itemProvider
                let isImage = provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
                let isMovie = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
                guard isImage || isMovie else { continue }
                let typeId = isImage ? UTType.image.identifier : UTType.movie.identifier
                let mime = isImage ? "image/jpeg" : "video/mp4"
                group.enter()
                provider.loadDataRepresentation(forTypeIdentifier: typeId) { data, error in
                    if let data, error == nil {
                        DispatchQueue.main.async { loaded[index] = (data, mime); group.leave() }
                    } else {
                        group.leave()
                    }
                }
            }
            group.notify(queue: .main) {
                let items = loaded.compactMap { $0 }
                if !items.isEmpty { completion(items) }
            }
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            picker.dismiss(animated: true)
            if let image = info[.originalImage] as? UIImage,
               let imageData = image.jpegData(compressionQuality: 0.8) {
                onMediaSelected(imageData, "image/jpeg")
            } else if let videoURL = info[.mediaURL] as? URL,
                      let videoData = try? Data(contentsOf: videoURL) {
                onMediaSelected(videoData, "video/mp4")
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    var allowsMultipleSelection = true
    /// Called once with every picked file (data, file name, mime type), in the order picked.
    let onDocumentsSelected: ([(Data, String, String)]) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = allowsMultipleSelection
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDocumentsSelected: onDocumentsSelected)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDocumentsSelected: ([(Data, String, String)]) -> Void
        
        init(onDocumentsSelected: @escaping ([(Data, String, String)]) -> Void) {
            self.onDocumentsSelected = onDocumentsSelected
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            var picked: [(Data, String, String)] = []
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                guard let data = try? Data(contentsOf: url) else { continue }
                let fileExtension = url.pathExtension.lowercased()
                let mimeType: String
                switch fileExtension {
                case "pdf": mimeType = "application/pdf"
                case "doc", "docx": mimeType = "application/msword"
                case "xls", "xlsx": mimeType = "application/vnd.ms-excel"
                case "txt": mimeType = "text/plain"
                case "png": mimeType = "image/png"
                case "jpg", "jpeg": mimeType = "image/jpeg"
                case "mp4": mimeType = "video/mp4"
                case "mov": mimeType = "video/quicktime"
                default: mimeType = "application/octet-stream"
                }
                picked.append((data, url.lastPathComponent, mimeType))
            }
            if !picked.isEmpty {
                DispatchQueue.main.async { self.onDocumentsSelected(picked) }
            }
        }
    }
}
#endif
