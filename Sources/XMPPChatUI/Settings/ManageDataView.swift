//
//  ManageDataView.swift
//  XMPPChatUI
//
//  "Manage data" screen: download a copy of your data (GET /v1/users/exportData)
//  and delete the account (DELETE /v1/users). Deleting signs the user out, the
//  same as an explicit log out.
//

import SwiftUI
import XMPPChatCore
#if os(iOS)
import UIKit
#endif

public struct ManageDataView: View {
    @State private var isExporting = false
    @State private var exportedFile: ExportedFile?
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false

    public init() {}

    public var body: some View {
        Form {
            Section {
                Text(UIStrings.t("settings.manageData.downloadDescription"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Button(action: exportData) {
                    HStack {
                        Text(UIStrings.t("settings.manageData.downloadLabel"))
                        Spacer()
                        if isExporting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isExporting)
            } header: {
                Text(UIStrings.t("settings.manageData.section.export"))
            }

            Section {
                Text(UIStrings.t("settings.manageData.deleteDescription"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Text(UIStrings.t("settings.manageData.deleteDisclosure"))
                    .font(.footnote)
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Text(UIStrings.t("action.deleteMyAccount"))
                        Spacer()
                        if isDeleting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isDeleting)
            } header: {
                Text(UIStrings.t("settings.manageData.deleteLabel"))
            }

            if let errorMessage = errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle(UIStrings.t("settings.manageData.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exportedFile) { file in
            ActivityView(items: [file.url])
        }
        #endif
        .alert(
            UIStrings.t("settings.manageData.deleteConfirmTitle"),
            isPresented: $showDeleteConfirmation
        ) {
            Button(UIStrings.t("action.cancel"), role: .cancel) {}
            Button(UIStrings.t("action.deleteMyAccount"), role: .destructive) {
                deleteAccount()
            }
        } message: {
            Text(UIStrings.t("settings.manageData.deleteConfirmDescription"))
        }
    }

    private func exportData() {
        isExporting = true
        errorMessage = nil
        Task { @MainActor in
            defer { isExporting = false }
            do {
                let data = try await AccountAPI.exportMyData()
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("ethora-export-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent("mydata.json")
                try data.write(to: url, options: .atomic)
                exportedFile = ExportedFile(url: url)
            } catch {
                errorMessage = UIStrings.t("settings.manageData.exportFailed")
            }
        }
    }

    private func deleteAccount() {
        guard !isDeleting else { return }
        isDeleting = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try await AccountAPI.deleteAccount()
                isDeleting = false
                await LogoutManager.shared.logout(client: ClientRegistry.shared.getGlobalXMPPClient())
            } catch {
                isDeleting = false
                errorMessage = UIStrings.t("settings.manageData.deleteFailed")
            }
        }
    }
}

/// A file ready to share, identified for `.sheet(item:)`.
struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL
}

#if os(iOS)
/// The system share sheet, used to save or send the exported file.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
