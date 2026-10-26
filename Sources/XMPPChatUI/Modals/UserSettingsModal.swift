//
//  UserSettingsModal.swift
//  XMPPChatUI
//
//  Settings sheet. Hosts AccountSettingsView (languages, change password, manage
//  data, log out). The public initializer is unchanged.
//

import SwiftUI
import XMPPChatCore

public struct UserSettingsModal: View {
    let user: User
    let onUpdate: (User) -> Void
    let onClose: () -> Void

    @Environment(\.dismiss) var dismiss

    public init(
        user: User,
        onUpdate: @escaping (User) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.user = user
        self.onUpdate = onUpdate
        self.onClose = onClose
    }

    public var body: some View {
        NavigationView {
            AccountSettingsView(onSignedOut: {
                dismiss()
                onClose()
            })
            .navigationTitle(UIStrings.t("settings.menu.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(UIStrings.t("action.close")) {
                        dismiss()
                        onClose()
                    }
                }
            }
        }
    }
}
