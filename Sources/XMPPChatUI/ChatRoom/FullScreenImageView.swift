//
//  FullScreenImageView.swift
//  XMPPChatUI
//

import SwiftUI

struct FullScreenImageView: View {
    let imageURL: URL
    let onClose: () -> Void
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var loadedImage: UIImage? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var useAsyncImageFallback = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if useAsyncImageFallback {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .tint(.white)
                    case .success(let img):
                        img
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        scale = lastScale * value
                                    }
                                    .onEnded { _ in
                                        lastScale = scale
                                        if scale < 1.0 {
                                            withAnimation {
                                                scale = 1.0
                                                lastScale = 1.0
                                                offset = .zero
                                                lastOffset = .zero
                                            }
                                        } else if scale > 3.0 {
                                            withAnimation {
                                                scale = 3.0
                                                lastScale = 3.0
                                            }
                                        }
                                    }
                            )
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                            )
                    case .failure:
                        VStack(spacing: 16) {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.white)
                            Text("Failed to load image")
                                .foregroundColor(.white)
                                .font(.headline)
                            Button("Retry") {
                                useAsyncImageFallback = false
                                isLoading = true
                                loadedImage = nil
                                errorMessage = nil
                                loadImage()
                            }
                            .padding()
                            .background(Color.white.opacity(0.2))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                    @unknown default:
                        ProgressView()
                            .tint(.white)
                    }
                }
            } else if isLoading && loadedImage == nil && errorMessage == nil {
                ProgressView()
                    .tint(.white)
            } else if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = lastScale * value
                            }
                            .onEnded { _ in
                                lastScale = scale
                                if scale < 1.0 {
                                    withAnimation {
                                        scale = 1.0
                                        lastScale = 1.0
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                } else if scale > 3.0 {
                                    withAnimation {
                                        scale = 3.0
                                        lastScale = 3.0
                                    }
                                }
                            }
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                    Text("Failed to load image")
                        .foregroundColor(.white)
                        .font(.headline)
                    Text(error)
                        .foregroundColor(.white.opacity(0.7))
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Retry") {
                        isLoading = true
                        loadedImage = nil
                        errorMessage = nil
                        loadImage()
                    }
                    .padding()
                    .background(Color.white.opacity(0.2))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            } else {
                ProgressView()
                    .tint(.white)
            }
            
            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.6))
                                .frame(width: 44, height: 44)
                            
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.trailing, 16)
                }
                Spacer()
            }
        }
        .onAppear {
            if loadedImage == nil {
                loadImage()
            }
        }
    }
    
    private func loadImage() {
        guard imageURL.scheme != nil, imageURL.host != nil else {
            errorMessage = "Invalid image URL"
            isLoading = false
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            var attempts = 0
            let maxAttempts = 3
            
            while attempts < maxAttempts {
                do {
                    let config = URLSessionConfiguration.default
                    config.timeoutIntervalForRequest = 15
                    let session = URLSession(configuration: config)
                    
                    var request = URLRequest(url: imageURL)
                    request.timeoutInterval = 15
                    request.cachePolicy = .returnCacheDataElseLoad
                    
                    let (data, response) = try await withTaskTimeout(seconds: 15) {
                        try await session.data(for: request)
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw NSError(domain: "ImageLoadingError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                    }
                    
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        throw NSError(domain: "ImageLoadingError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP Error: \(httpResponse.statusCode)"])
                    }
                    
                    guard let image = UIImage(data: data) else {
                        throw NSError(domain: "ImageLoadingError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create image from data"])
                    }
                    
                    await MainActor.run {
                        loadedImage = image
                        isLoading = false
                        errorMessage = nil
                    }
                    return
                    
                } catch {
                    attempts += 1
                    if attempts >= maxAttempts {
                        await MainActor.run {
                            useAsyncImageFallback = true
                            isLoading = false
                            errorMessage = nil
                        }
                    } else {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                }
            }
        }
    }
    
    private func withTaskTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(domain: "TimeoutError", code: -3, userInfo: [NSLocalizedDescriptionKey: "Request timed out after \(seconds) seconds"])
            }
            guard let result = try await group.next() else {
                throw NSError(domain: "TimeoutError", code: -3, userInfo: [NSLocalizedDescriptionKey: "No result received"])
            }
            group.cancelAll()
            return result
        }
    }
}
