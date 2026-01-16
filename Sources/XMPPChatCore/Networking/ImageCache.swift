//
//  ImageCache.swift
//  XMPPChatCore
//
//  Image caching system for performance optimization
//

import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit

public class ImageCache {
    public static let shared = ImageCache()
    
    private let cache = NSCache<NSString, UIImage>()
    private let maxCacheSize: Int = 50 * 1024 * 1024 // 50 MB
    
    private init() {
        cache.totalCostLimit = maxCacheSize
        cache.countLimit = 100
    }
    
    public func getImage(for url: String) -> UIImage? {
        return cache.object(forKey: url as NSString)
    }
    
    public func setImage(_ image: UIImage, for url: String) {
        let cost = image.size.width * image.size.height * 4 // Rough estimate
        cache.setObject(image, forKey: url as NSString, cost: Int(cost))
    }
    
    public func removeImage(for url: String) {
        cache.removeObject(forKey: url as NSString)
    }
    
    public func clearCache() {
        cache.removeAllObjects()
    }
}

#elseif canImport(AppKit)
import AppKit

public class ImageCache {
    public static let shared = ImageCache()
    
    private let cache = NSCache<NSString, NSImage>()
    private let maxCacheSize: Int = 50 * 1024 * 1024 // 50 MB
    
    private init() {
        cache.totalCostLimit = maxCacheSize
        cache.countLimit = 100
    }
    
    public func getImage(for url: String) -> NSImage? {
        return cache.object(forKey: url as NSString)
    }
    
    public func setImage(_ image: NSImage, for url: String) {
        let cost = image.size.width * image.size.height * 4 // Rough estimate
        cache.setObject(image, forKey: url as NSString, cost: Int(cost))
    }
    
    public func removeImage(for url: String) {
        cache.removeObject(forKey: url as NSString)
    }
    
    public func clearCache() {
        cache.removeAllObjects()
    }
}
#endif
