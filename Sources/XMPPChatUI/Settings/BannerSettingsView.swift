//
//  BannerSettingsView.swift
//  XMPPChatUI
//
//  Settings view for configuring off-clinic hours banner
//

import SwiftUI
import XMPPChatCore

public struct BannerSettingsView: View {
    @ObservedObject private var bannerStore = BannerSettingsStore.shared
    @State private var isEnabled: Bool
    @State private var startHour: Int
    @State private var endHour: Int
    @State private var bannerText: String
    
    public init() {
        let settings = BannerSettingsStore.shared.settings
        _isEnabled = State(initialValue: settings.isEnabled)
        _startHour = State(initialValue: settings.startHour)
        _endHour = State(initialValue: settings.endHour)
        _bannerText = State(initialValue: settings.bannerText)
    }
    
    public var body: some View {
        Form {
            Section(header: Text("Off-Clinic Hours Banner")) {
                Toggle("Enable Banner", isOn: $isEnabled)
                    .onChange(of: isEnabled) { newValue in
                        bannerStore.updateSettings(isEnabled: newValue)
                    }
                
                if isEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Banner Text")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        TextField("off-clinic hours", text: $bannerText)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: bannerText) { newValue in
                                bannerStore.updateSettings(bannerText: newValue)
                            }
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Active Hours")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Start Hour")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Picker("Start Hour", selection: $startHour) {
                                    ForEach(0..<24) { hour in
                                        Text("\(hour):00").tag(hour)
                                    }
                                }
                                .pickerStyle(.menu)
                                .onChange(of: startHour) { newValue in
                                    bannerStore.updateSettings(startHour: newValue)
                                }
                            }
                            
                            Spacer()
                            
                            Text("to")
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            VStack(alignment: .leading) {
                                Text("End Hour")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Picker("End Hour", selection: $endHour) {
                                    ForEach(0..<24) { hour in
                                        Text("\(hour):00").tag(hour)
                                    }
                                }
                                .pickerStyle(.menu)
                                .onChange(of: endHour) { newValue in
                                    bannerStore.updateSettings(endHour: newValue)
                                }
                            }
                        }
                        
                        // Show preview of active time range
                        if endHour < startHour {
                            Text("Active from \(startHour):00 to \(endHour):00 (next day)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                        } else {
                            Text("Active from \(startHour):00 to \(endHour):00")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Section(header: Text("Preview")) {
                if isEnabled && bannerStore.settings.isCurrentlyActive() {
                    HStack {
                        Spacer()
                        Text(bannerText)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        Spacer()
                    }
                    .background(Color.orange)
                    .cornerRadius(8)
                } else {
                    Text("Banner is currently inactive")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
        .navigationTitle("Banner Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

