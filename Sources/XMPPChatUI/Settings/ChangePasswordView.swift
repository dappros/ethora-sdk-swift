//
//  ChangePasswordView.swift
//  XMPPChatUI
//
//  "Change password" screen: PUT /v2/users/me/password. Shown when
//  `settings.changePassword` is true. The server's reason is shown on failure.
//

import SwiftUI
import XMPPChatCore

public struct ChangePasswordView: View {
    /// Matches the sign-up rule (web validation.passwordTooShort).
    static let minimumLength = 6

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var repeatPassword = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didChange = false
    @Environment(\.dismiss) private var dismiss

    public init() {}

    /// The reason the new password can not be submitted yet, or nil when it can.
    static func validationMessage(current: String, new: String, repeated: String) -> String? {
        if new.count < minimumLength {
            return UIStrings.t("settings.password.tooShort", ["min": String(minimumLength)])
        }
        if new == current {
            return UIStrings.t("settings.password.sameAsCurrent")
        }
        if new != repeated {
            return UIStrings.t("settings.password.mismatch")
        }
        return nil
    }

    private var validation: String? {
        guard !currentPassword.isEmpty, !newPassword.isEmpty || !repeatPassword.isEmpty else { return nil }
        return Self.validationMessage(current: currentPassword, new: newPassword, repeated: repeatPassword)
    }

    private var canSubmit: Bool {
        !currentPassword.isEmpty
            && !newPassword.isEmpty
            && !repeatPassword.isEmpty
            && Self.validationMessage(current: currentPassword, new: newPassword, repeated: repeatPassword) == nil
            && !isSaving
    }

    public var body: some View {
        Form {
            Section {
                SecureField(UIStrings.t("settings.password.current"), text: $currentPassword)
                    .textContentType(.password)
                SecureField(UIStrings.t("settings.password.new"), text: $newPassword)
                    .textContentType(.newPassword)
                SecureField(UIStrings.t("settings.password.again"), text: $repeatPassword)
                    .textContentType(.newPassword)
            } footer: {
                Text(validation ?? UIStrings.t("settings.password.hint"))
                    .foregroundColor(validation == nil ? .secondary : .red)
            }

            if let errorMessage = errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
            }

            if didChange {
                Section {
                    Text(UIStrings.t("settings.password.changed"))
                        .foregroundColor(.green)
                }
            }

            Section {
                Button(action: submit) {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(UIStrings.t("settings.password.submit"))
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(!canSubmit)
            }
        }
        .navigationTitle(UIStrings.t("settings.password.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func submit() {
        guard canSubmit else { return }
        isSaving = true
        errorMessage = nil
        let current = currentPassword
        let new = newPassword
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await AccountAPI.changePassword(currentPassword: current, newPassword: new)
                didChange = true
                currentPassword = ""
                newPassword = ""
                repeatPassword = ""
            } catch let error as AccountAPI.AccountError {
                if case .server(let status, let reason) = error {
                    errorMessage = reason ?? (status == 401 || status == 403
                        ? UIStrings.t("settings.password.wrongCurrent")
                        : UIStrings.t("settings.password.failed"))
                } else {
                    errorMessage = UIStrings.t("settings.password.failed")
                }
            } catch {
                errorMessage = UIStrings.t("settings.password.failed")
            }
        }
    }
}
