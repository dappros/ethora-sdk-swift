//
//  AudioWaveformView.swift
//  XMPPChatUI
//
//  Real audio waveform visualization
//

import SwiftUI
import AVFoundation
import Accelerate
import XMPPChatCore

public struct AudioWaveformView: View {
    let audioURL: URL
    let waveformData: [Float]?
    let waveColor: Color
    let progressColor: Color
    let onSeek: ((Double) -> Void)?
    
    @State private var waveformPoints: [CGPoint] = []
    @State private var progress: Double = 0
    @State private var isDragging: Bool = false
    @State private var dragLocation: CGFloat = 0
    
    public init(
        audioURL: URL,
        waveformData: [Float]? = nil,
        waveColor: Color = Color.gray.opacity(0.6),
        progressColor: Color = Color.blue,
        onSeek: ((Double) -> Void)? = nil
    ) {
        self.audioURL = audioURL
        self.waveformData = waveformData
        self.waveColor = waveColor
        self.progressColor = progressColor
        self.onSeek = onSeek
    }
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background waveform
                WaveformPath(
                    points: waveformPoints,
                    color: waveColor,
                    width: geometry.size.width,
                    height: geometry.size.height
                )
                
                // Progress waveform
                if progress > 0 {
                    WaveformPath(
                        points: Array(waveformPoints.prefix(Int(Double(waveformPoints.count) * progress))),
                        color: progressColor,
                        width: geometry.size.width * CGFloat(progress),
                        height: geometry.size.height
                    )
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        dragLocation = value.location.x
                        let seekProgress = min(max(0, value.location.x / geometry.size.width), 1.0)
                        onSeek?(seekProgress)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .frame(height: 40)
        .onAppear {
            if let waveformData = waveformData {
                generateWaveform(from: waveformData)
            } else {
                generateWaveformFromAudio()
            }
        }
    }
    
    private func generateWaveform(from data: [Float]) {
        // Normalize and create points
        let maxValue = data.max() ?? 1.0
        waveformPoints = data.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index),
                y: CGFloat(value / maxValue)
            )
        }
    }
    
    private func generateWaveformFromAudio() {
        Task {
            do {
                let audioFile = try AVAudioFile(forReading: audioURL)
                let format = audioFile.processingFormat
                let frameCount = UInt32(audioFile.length)
                
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                    return
                }
                
                try audioFile.read(into: buffer)
                
                guard let channelData = buffer.floatChannelData else { return }
                let channelDataValue = channelData.pointee
                let channelDataValueArray = stride(from: 0, to: Int(buffer.frameLength), by: buffer.stride)
                    .map { channelDataValue[$0] }
                
                // Downsample for visualization
                let sampleCount = 100
                let step = max(1, channelDataValueArray.count / sampleCount)
                let samples = stride(from: 0, to: channelDataValueArray.count, by: step)
                    .map { abs(channelDataValueArray[$0]) }
                
                await MainActor.run {
                    generateWaveform(from: samples)
                }
            } catch {
                print("Error generating waveform: \(error)")
                // Fallback to placeholder
                await MainActor.run {
                    waveformPoints = (0..<100).map { index in
                        CGPoint(
                            x: CGFloat(index),
                            y: CGFloat.random(in: 0.2...1.0)
                        )
                    }
                }
            }
        }
    }
}

struct WaveformPath: View {
    let points: [CGPoint]
    let color: Color
    let width: CGFloat
    let height: CGFloat
    
    var body: some View {
        Path { path in
            guard !points.isEmpty else { return }
            
            let barWidth = width / CGFloat(max(points.count, 1))
            
            for (index, point) in points.enumerated() {
                let x = CGFloat(index) * barWidth
                let barHeight = point.y * height
                let y = (height - barHeight) / 2
                
                path.addRect(CGRect(x: x, y: y, width: barWidth - 1, height: barHeight))
            }
        }
        .fill(color)
    }
}
