//
//  AccountSettingsView.swift
//  XMPPChatUI
//
//  The settings screen: languages, change password, manage data, and log out
//  with a confirmation. Each part follows its config switch (see ChatConfig.settings).
//

import SwiftUI
import XMPPChatCore

public struct AccountSettingsView: View {
    /// Called after a log out or account deletion completes.
    let onSignedOut: (() -> Void)?

    @ObservedObject private var configStore = ConfigStore.shared
    @State private var showLogoutConfirmation = false
    @State private var isLoggingOut = false

    public init(onSignedOut: (() -> Void)? = nil) {
        self.onSignedOut = onSignedOut
    }

    private var settings: AccountSettingsConfig? { configStore.config.settings }

    public var body: some View {
        Form {
            if settings?.languages?.enabled == true {
                LanguageSettingsCard()
            }

            if settings?.changePassword == true {
                Section {
                    NavigationLink {
                        ChangePasswordView()
                    } label: {
                        Text(UIStrings.t("settings.password.title"))
                    }
                }
            }

            Section {
                NavigationLink {
                    ManageDataView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(UIStrings.t("settings.manageData.title"))
                        Text(UIStrings.t("settings.manageData.rowHint"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text(UIStrings.t("settings.section.privacy"))
            }

            Section {
                Button(role: .destructive) {
                    showLogoutConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Text(UIStrings.t("action.logOut"))
                        Spacer()
                    }
                }
                .disabled(isLoggingOut)
            }
        }
        .alert(
            UIStrings.t("settings.logout.confirmTitle"),
            isPresented: $showLogoutConfirmation
        ) {
            Button(UIStrings.t("action.cancel"), role: .cancel) {}
            Button(UIStrings.t("action.logOut"), role: .destructive) {
                logOut()
            }
        } message: {
            Text(UIStrings.t("settings.logout.confirmMessage"))
        }
    }

    private func logOut() {
        guard !isLoggingOut else { return }
        isLoggingOut = true
        Task { @MainActor in
            await LogoutManager.shared.logout(client: ClientRegistry.shared.getGlobalXMPPClient())
            isLoggingOut = false
            onSignedOut?()
        }
    }
}
