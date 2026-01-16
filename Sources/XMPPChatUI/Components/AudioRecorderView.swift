//
//  AudioRecorderView.swift
//  XMPPChatUI
//
//  Audio recording component matching web version
//

import SwiftUI
import AVFoundation
import Combine

#if os(iOS)
public struct AudioRecorderView: View {
    @Binding var isRecording: Bool
    let onAudioRecorded: (Data, String) -> Void
    let onCancel: (() -> Void)?
    
    @StateObject private var recorder = AudioRecorderManager()
    @State private var timer: Int = 0
    @State private var timerTask: Task<Void, Never>?
    
    public init(
        isRecording: Binding<Bool>,
        onAudioRecorded: @escaping (Data, String) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self._isRecording = isRecording
        self.onAudioRecorded = onAudioRecorded
        self.onCancel = onCancel
    }
    
    public var body: some View {
        if isRecording {
            recordingView
        } else {
            recordButton
        }
    }
    
    private var recordButton: some View {
        Button(action: {
            startRecording()
        }) {
            Image(systemName: "mic.fill")
                .font(.title3)
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Color.red)
                .clipShape(Circle())
        }
    }
    
    private var recordingView: some View {
        HStack(spacing: 12) {
            // Recording indicator with animation
            RecordingIndicatorView()
            
            // Timer
            Text(formatTime(timer))
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)
            
            Spacer()
            
            // Cancel button
            Button(action: {
                cancelRecording()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.red)
            }
            
            // Send button
            Button(action: {
                sendRecording()
            }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }
    
    private func startRecording() {
        Task {
            do {
                try await recorder.startRecording()
                isRecording = true
                startTimer()
            } catch {
                print("Failed to start recording: \(error)")
            }
        }
    }
    
    private func cancelRecording() {
        recorder.stopRecording()
        stopTimer()
        timer = 0
        isRecording = false
        onCancel?()
    }
    
    private func sendRecording() {
        Task {
            if let audioData = await recorder.stopAndGetData() {
                onAudioRecorded(audioData, "audio/m4a")
            }
            stopTimer()
            timer = 0
            isRecording = false
        }
    }
    
    private func startTimer() {
        timer = 0
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                if !Task.isCancelled {
                    await MainActor.run {
                        timer += 1
                    }
                }
            }
        }
    }
    
    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// MARK: - Recording Indicator with Animation
struct RecordingIndicatorView: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
                .scaleEffect(isAnimating ? 1.3 : 1.0)
                .opacity(isAnimating ? 0.5 : 1.0)
                .animation(
                    Animation.easeInOut(duration: 1.0)
                        .repeatForever(autoreverses: true),
                    value: isAnimating
                )
            
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Audio Recorder Manager
@MainActor
class AudioRecorderManager: NSObject, ObservableObject {
    private var audioRecorder: AVAudioRecorder?
    private var audioSession: AVAudioSession = AVAudioSession.sharedInstance()
    private var recordingURL: URL?
    
    func startRecording() async throws {
        // Request permission
        let granted = await withCheckedContinuation { continuation in
            audioSession.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard granted else {
            throw AudioRecorderError.permissionDenied
        }
        
        // Configure audio session
        try audioSession.setCategory(.playAndRecord, mode: .default)
        try audioSession.setActive(true)
        
        // Create temporary file URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        recordingURL = documentsPath.appendingPathComponent("recording_\(UUID().uuidString).m4a")
        
        guard let url = recordingURL else {
            throw AudioRecorderError.fileCreationFailed
        }
        
        // Audio settings
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        // Create recorder
        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.record()
    }
    
    func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        try? audioSession.setActive(false)
    }
    
    func stopAndGetData() async -> Data? {
        guard let url = recordingURL else { return nil }
        audioRecorder?.stop()
        audioRecorder = nil
        try? audioSession.setActive(false)
        
        // Read audio data
        guard let data = try? Data(contentsOf: url) else { return nil }
        
        // Clean up
        try? FileManager.default.removeItem(at: url)
        recordingURL = nil
        
        return data
    }
}

extension AudioRecorderManager: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("Recording finished unsuccessfully")
        }
    }
}

enum AudioRecorderError: Error {
    case permissionDenied
    case fileCreationFailed
    case recordingFailed
}

#else
// macOS placeholder
public struct AudioRecorderView: View {
    @Binding var isRecording: Bool
    let onAudioRecorded: (Data, String) -> Void
    let onCancel: (() -> Void)?
    
    public var body: some View {
        EmptyView()
    }
}
#endif
