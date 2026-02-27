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
    let onMediaSelected: (Data, String) -> Void
    
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
            
            configuration.selectionLimit = 1
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = context.coordinator
            return picker
        }
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onMediaSelected: onMediaSelected)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onMediaSelected: (Data, String) -> Void
        
        init(onMediaSelected: @escaping (Data, String) -> Void) {
            self.onMediaSelected = onMediaSelected
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
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
    let onDocumentSelected: (Data, String, String) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDocumentSelected: onDocumentSelected)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDocumentSelected: (Data, String, String) -> Void
        
        init(onDocumentSelected: @escaping (Data, String, String) -> Void) {
            self.onDocumentSelected = onDocumentSelected
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                let data = try Data(contentsOf: url)
                let fileName = url.lastPathComponent
                let fileExtension = url.pathExtension.lowercased()
                
                let mimeType: String
                switch fileExtension {
                case "pdf": mimeType = "application/pdf"
                case "doc", "docx": mimeType = "application/msword"
                case "xls", "xlsx": mimeType = "application/vnd.ms-excel"
                case "txt": mimeType = "text/plain"
                default: mimeType = "application/octet-stream"
                }
                
                DispatchQueue.main.async {
                    self.onDocumentSelected(data, fileName, mimeType)
                }
            } catch {}
        }
    }
}
#endif
