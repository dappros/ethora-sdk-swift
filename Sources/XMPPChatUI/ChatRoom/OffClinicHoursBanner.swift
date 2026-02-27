//
//  OffClinicHoursBanner.swift
//  XMPPChatUI
//

import SwiftUI
import XMPPChatCore

struct OffClinicHoursBanner: View {
    @ObservedObject private var bannerStore = BannerSettingsStore.shared
    @State private var isActive = false
    @State private var timer: Timer?
    
    var body: some View {
        Group {
            if isActive {
                HStack {
                    Spacer()
                    Text(bannerStore.settings.bannerText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    Spacer()
                }
                .background(Color.orange)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            checkAndUpdate()
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
        .onChange(of: bannerStore.settings.isEnabled) { _ in
            checkAndUpdate()
        }
        .onChange(of: bannerStore.settings.startHour) { _ in
            checkAndUpdate()
        }
        .onChange(of: bannerStore.settings.endHour) { _ in
            checkAndUpdate()
        }
        .onChange(of: bannerStore.settings.bannerText) { _ in
            checkAndUpdate()
        }
    }
    
    private func checkAndUpdate() {
        let newActive = bannerStore.settings.isCurrentlyActive()
        withAnimation(.easeInOut(duration: 0.3)) {
            isActive = newActive
        }
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
            checkAndUpdate()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
