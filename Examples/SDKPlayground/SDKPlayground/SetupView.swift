//
//  SetupView.swift
//  SDKPlayground
//

import SwiftUI
import XMPPChatCore

struct SetupView: View {
    private enum AuthInputMode: String, CaseIterable, Identifiable {
        case fields = "Fields"
        case json = "JSON"
        var id: String { rawValue }
    }

    @EnvironmentObject private var session: PlaygroundSession
    @EnvironmentObject private var logs: PlaygroundLogStore
    @State private var isAuthAccordionExpanded = true
    @State private var isUIAccordionExpanded = false
    @State private var authInputMode: AuthInputMode = .fields
    @State private var authJSONInput: String = """
{
  "connectionProfile": "ethoraDev",
  "auth": {
    "mode": "email",
    "email": "user@mail.com",
    "password": "secret"
  },
  "api": {
    "baseUrl": "https://api.chat.ethora.com/v1",
    "appToken": "",
    "appId": "",
    "useJwtPrefix": true
  },
  "xmpp": {
    "webSocketUrl": "wss://xmpp.chat.ethora.com/ws",
    "host": "xmpp.chat.ethora.com",
    "conference": "conference.xmpp.chat.ethora.com"
  },
  "chat": {
    "singleRoomMode": false,
    "roomJid": "699c6923429c2757ac8ab6a4_playground-room-1@conference.xmpp.chat.ethora.com"
  }
}
"""
    @State private var authJSONStatus: String?

    var body: some View {
        NavigationView {
            Form {
                Section {
                    DisclosureGroup("Authorization", isExpanded: $isAuthAccordionExpanded) {
                        Picker("Connection profile", selection: $session.connectionPreset) {
                            ForEach(PlaygroundSession.ConnectionPreset.allCases) { preset in
                                Text(preset.rawValue).tag(preset)
                            }
                        }
                        .onChange(of: session.connectionPreset) { _ in
                            session.applyConnectionPreset()
                        }
                        
                        Picker("Auth", selection: $session.authMode) {
                            ForEach(PlaygroundSession.AuthMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }

                        Picker("Input mode", selection: $authInputMode) {
                            ForEach(AuthInputMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        if authInputMode == .fields {
                            TextField("Base URL", text: $session.baseURLString)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            TextField("App token (API key)", text: $session.appToken)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Toggle("Use JWT prefix in Authorization (Ethora)", isOn: $session.useEthoraJwtWordPrefixForAppToken)
                            TextField("App ID", text: $session.appId)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            
                            if session.authMode == .jwtCustom {
                                SecureField("JWT (custom token → x-custom-token)", text: $session.jwtToken)
                            } else {
                                TextField("Email", text: $session.email)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.emailAddress)
                                SecureField("Password", text: $session.password)
                            }
                            
                            TextField("XMPP WebSocket URL", text: $session.xmppWebSocketURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            TextField("XMPP host", text: $session.xmppHost)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            TextField("Conference domain", text: $session.xmppConference)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            
                            Toggle("Single chat mode (hide rooms list)", isOn: $session.useSingleChatMode)
                            if session.useSingleChatMode {
                                TextField("Room JID", text: $session.singleChatRoomJID)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Paste a configuration JSON object")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextEditor(text: $authJSONInput)
                                    .frame(minHeight: 180)
                                    .font(.system(.footnote, design: .monospaced))
                                HStack {
                                    Button("Format JSON") {
                                        do {
                                            authJSONInput = try prettyPrintedJSON(authJSONInput)
                                            authJSONStatus = "JSON formatted."
                                        } catch {
                                            authJSONStatus = "JSON error: \(error.localizedDescription)"
                                        }
                                    }
                                    Button("Copy JSON") {
                                        do {
                                            let formatted = try prettyPrintedJSON(authJSONInput)
                                            authJSONInput = formatted
                                            copyToClipboard(formatted)
                                            authJSONStatus = "JSON copied to clipboard."
                                        } catch {
                                            authJSONStatus = "JSON error: \(error.localizedDescription)"
                                        }
                                    }
                                    Button("Apply JSON") {
                                        do {
                                            let formatted = try prettyPrintedJSON(authJSONInput)
                                            authJSONInput = formatted
                                            try session.applySetupJSONObject(formatted)
                                            authJSONStatus = "JSON applied successfully."
                                        } catch {
                                            authJSONStatus = "JSON error: \(error.localizedDescription)"
                                        }
                                    }
                                }
                                if let status = authJSONStatus {
                                    Text(status)
                                        .font(.caption)
                                        .foregroundStyle(status.hasPrefix("JSON error") ? .red : .green)
                                }
                            }
                        }

                        Button {
                            logs.append("UI: Connect tapped", level: .info)
                            Task {
                                await session.connect(log: logs)
                            }
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.accentColor.opacity(session.isBusy ? 0.25 : 0.18))
                                if session.isBusy {
                                    ProgressView()
                                        .tint(.accentColor)
                                } else {
                                    Text("Connect")
                                        .fontWeight(.semibold)
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                        }
                        .padding(.top, 14)
                        .listRowSeparator(.hidden)
                        .disabled(session.isBusy)

                        Button(role: .destructive) {
                            logs.append("UI: Disconnect tapped", level: .warning)
                            Task {
                                await session.disconnect(log: logs)
                            }
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.red.opacity(0.14))
                                Text("Disconnect")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.red)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                        }
                        .padding(.top, 8)
                        .listRowSeparator(.hidden)
                        .disabled(session.isBusy)

                        HStack {
                            Text("Chat ready")
                            Spacer()
                            Text(session.isConnected ? "Yes" : "No")
                                .foregroundColor(session.isConnected ? .green : .secondary)
                        }
                        .padding(.top, 10)
                    }
                } header: {
                    Text("Authorization")
                } footer: {
                    Text("Connection profile: Ethora Dev = default Ethora config; Custom = manual values.")
                }
                
                Section {
                    DisclosureGroup("UI settings", isExpanded: $isUIAccordionExpanded) {
                        Picker("Theme", selection: $session.appTheme) {
                            ForEach(PlaygroundSession.AppTheme.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        ColorConfigField(
                            title: "Primary color",
                            usage: "Primary UI accent: buttons, active controls, and key chat highlights.",
                            value: $session.primaryColorHex
                        )
                        ColorConfigField(
                            title: "Secondary color",
                            usage: "Secondary UI accent: supporting controls and subtle backgrounds.",
                            value: $session.secondaryColorHex
                        )
                        ColorConfigField(
                            title: "Incoming message background",
                            usage: "Background color of incoming messages (messages from other users).",
                            value: $session.incomingMessageColorHex
                        )
                        ColorConfigField(
                            title: "Outgoing message background",
                            usage: "Background color of outgoing messages (your messages).",
                            value: $session.outgoingMessageColorHex
                        )
                        ColorConfigField(
                            title: "Incoming message text",
                            usage: "Text color for incoming messages.",
                            value: $session.incomingMessageTextColorHex
                        )
                        ColorConfigField(
                            title: "Outgoing message text",
                            usage: "Text color for outgoing messages.",
                            value: $session.outgoingMessageTextColorHex
                        )
                        ColorConfigField(
                            title: "Chat background (optional)",
                            usage: "Background color for the whole chat area. Empty = default/system background.",
                            value: $session.chatBackgroundColorHex
                        )
                    }
                } header: {
                    Text("UI")
                } footer: {
                    Text("These values are passed to ChatConfig (colors + bubleMessage + backgroundChat).")
                }

                if let err = session.lastError {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

            }
            .navigationTitle("Setup")
        }
    }
    
    private func prettyPrintedJSON(_ raw: String) throws -> String {
        let data = Data(raw.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        guard let result = String(data: pretty, encoding: .utf8) else {
            throw NSError(domain: "SetupView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to format JSON."])
        }
        return result
    }

    private func copyToClipboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

private struct ColorConfigField: View {
    let title: String
    let usage: String
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                ColorPicker("", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
            }
            Text(usage)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("#RRGGBB", text: $value)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.vertical, 4)
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                Color(hex: normalizedHex(value, fallback: "#000000"))
            },
            set: { newColor in
                if let hex = newColor.toHexRGB() {
                    value = hex
                }
            }
        )
    }

    private func normalizedHex(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
    }
}

private extension Color {
    func toHexRGB() -> String? {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        return String(
            format: "#%02X%02X%02X",
            Int(red * 255),
            Int(green * 255),
            Int(blue * 255)
        )
        #else
        return nil
        #endif
    }
}
