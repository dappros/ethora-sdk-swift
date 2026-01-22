//
//  MemoryMonitor.swift
//  XMPPChatCore
//
//  XMPP memory monitoring
//

import Foundation

#if os(iOS) || os(macOS)
public class XMPPMemoryMonitor {
    private var monitoringTimer: Timer?
    private var memoryReadings: [MemoryReading] = []
    private let maxReadings: Int = 100
    
    public var isMonitoring: Bool = false
    
    public init() {}
    
    public func startMonitoring(interval: TimeInterval = 5.0) {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.recordMemoryUsage()
        }
    }
    
    public func stopMonitoring() {
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }
    
    private func recordMemoryUsage() {
        let usage = getCurrentMemoryUsage()
        let reading = MemoryReading(timestamp: Date(), usage: usage)
        memoryReadings.append(reading)
        
        if memoryReadings.count > maxReadings {
            memoryReadings.removeFirst()
        }
        
        // Check for potential leaks
        if memoryReadings.count >= 10 {
            let recent = Array(memoryReadings.suffix(10))
            let average = recent.map { $0.usage }.reduce(0, +) / Double(recent.count)
            let current = usage
            
            if current > average * 1.5 {
                //print("⚠️ Potential memory leak detected: \(current)MB (average: \(average)MB)")
            }
        }
    }
    
    private func getCurrentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0 // Convert to MB
        }
        
        return 0.0
    }
    
    public func getMemoryStats() -> MemoryStats {
        let readings = memoryReadings
        guard !readings.isEmpty else {
            return MemoryStats(current: 0, average: 0, peak: 0)
        }
        
        let current = readings.last?.usage ?? 0
        let average = readings.map { $0.usage }.reduce(0, +) / Double(readings.count)
        let peak = readings.map { $0.usage }.max() ?? 0
        
        return MemoryStats(current: current, average: average, peak: peak)
    }
}

struct MemoryReading {
    let timestamp: Date
    let usage: Double // MB
}

public struct MemoryStats {
    public let current: Double
    public let average: Double
    public let peak: Double
}
#else
public class XMPPMemoryMonitor {
    public var isMonitoring: Bool = false
    public init() {}
    public func startMonitoring(interval: TimeInterval = 5.0) {}
    public func stopMonitoring() {}
    public func getMemoryStats() -> MemoryStats {
        return MemoryStats(current: 0, average: 0, peak: 0)
    }
}

public struct MemoryStats {
    public let current: Double
    public let average: Double
    public let peak: Double
}
#endif
