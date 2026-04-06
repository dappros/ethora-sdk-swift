//
//  SetupView.swift
//  SDKPlayground
//

import SwiftUI
import XMPPChatCore

struct SetupView: View {
    @EnvironmentObject private var session: PlaygroundSession
    @EnvironmentObject private var logs: PlaygroundLogStore

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("Auth", selection: $session.authMode) {
                        ForEach(PlaygroundSession.AuthMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                } header: {
                    Text("Authentication")
                }

                Section {
                    TextField("Base URL", text: $session.baseURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("App token (API key)", text: $session.appToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("Префикс JWT в Authorization (Ethora)", isOn: $session.useEthoraJwtWordPrefixForAppToken)
                    TextField("App ID", text: $session.appId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("API")
                } footer: {
                    Text("Bearer SDK никогда не дописывает; если вставили Bearer — только убираем. Слово JWT — не OAuth: для api.ethoradev.com по умолчанию нужен заголовок вида «JWT eyJ…» (как web). Выключите переключатель, если ваш бэкенд ждёт только «eyJ…» без слова JWT. Пустое поле = встроенный dev токен из SDK.")
                }

                if session.authMode == .jwtCustom {
                    Section {
                        SecureField("JWT (custom token → x-custom-token)", text: $session.jwtToken)
                    } header: {
                        Text("JWT")
                    } footer: {
                        Text("Uses POST /users/client (loginViaJwt).")
                    }
                } else {
                    Section {
                        TextField("Email", text: $session.email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                        SecureField("Password", text: $session.password)
                    } header: {
                        Text("Account")
                    }
                }

                Section {
                    TextField("XMPP WebSocket URL", text: $session.xmppWebSocketURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("XMPP host", text: $session.xmppHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Conference domain", text: $session.xmppConference)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("XMPP")
                } footer: {
                    Text("Optional overrides for `ChatConfig.xmppSettings` (xmppServerUrl, host, conference).")
                }

                Section {
                    Button {
                        Task {
                            await session.connect(log: logs)
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if session.isBusy {
                                ProgressView()
                            } else {
                                Text("Connect")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(session.isBusy)

                    Button(role: .destructive) {
                        Task {
                            await session.disconnect(log: logs)
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text("Disconnect")
                            Spacer()
                        }
                    }
                    .disabled(session.isBusy)
                }

                if let err = session.lastError {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    HStack {
                        Text("Chat ready")
                        Spacer()
                        Text(session.isConnected ? "Yes" : "No")
                            .foregroundColor(session.isConnected ? .green : .secondary)
                    }
                }
            }
            .navigationTitle("Setup")
        }
    }
}
