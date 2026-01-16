//
//  QRCodeView.swift
//  XMPPChatUI
//
//  QR code generation and display
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

public struct QRCodeView: View {
    let content: String
    let size: CGFloat
    
    public init(content: String, size: CGFloat = 200) {
        self.content = content
        self.size = size
    }
    
    public var body: some View {
        if let qrImage = generateQRCode(from: content) {
            #if os(iOS)
            Image(uiImage: qrImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
            #else
            Image(nsImage: qrImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
            #endif
        } else {
            Image(systemName: "qrcode")
                .font(.system(size: size))
                .foregroundColor(.gray)
        }
    }
    
    #if os(iOS)
    private func generateQRCode(from string: String) -> UIImage? {
        let data = string.data(using: String.Encoding.ascii)
        
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        guard let output = filter.outputImage?.transformed(by: transform) else { return nil }
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
    #else
    private func generateQRCode(from string: String) -> NSImage? {
        let data = string.data(using: String.Encoding.ascii)
        
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        guard let output = filter.outputImage?.transformed(by: transform) else { return nil }
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        
        let size = NSSize(width: output.extent.width, height: output.extent.height)
        let nsImage = NSImage(cgImage: cgImage, size: size)
        return nsImage
    }
    #endif
}

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
typealias UIImage = NSImage
#endif
