//
//  ReportModal.swift
//  XMPPChatUI
//
//  Report message or room modal
//

import SwiftUI
import XMPPChatCore

public struct ReportModal: View {
    let type: ReportType
    let onReport: (String, String) -> Void
    let onClose: () -> Void
    
    @State private var selectedReason: String = ""
    @State private var additionalInfo: String = ""
    @Environment(\.dismiss) var dismiss
    
    private let reportReasons = [
        "Spam",
        "Harassment",
        "Inappropriate Content",
        "Violence",
        "Other"
    ]
    
    public enum ReportType {
        case message
        case room
        case user
    }
    
    public init(
        type: ReportType,
        onReport: @escaping (String, String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.type = type
        self.onReport = onReport
        self.onClose = onClose
    }
    
    public var body: some View {
        NavigationView {
            Form {
                Section("Reason") {
                    Picker("Select Reason", selection: $selectedReason) {
                        ForEach(reportReasons, id: \.self) { reason in
                            Text(reason).tag(reason)
                        }
                    }
                }
                
                Section("Additional Information") {
                    if #available(iOS 16.0, macOS 13.0, *) {
                        TextField("Provide more details (optional)", text: $additionalInfo, axis: .vertical)
                            .lineLimit(3...6)
                    } else {
                        TextField("Provide more details (optional)", text: $additionalInfo)
                            .lineLimit(6)
                    }
                }
                
                Section {
                    Button(action: {
                        onReport(selectedReason, additionalInfo)
                        dismiss()
                    }) {
                        Text("Submit Report")
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(selectedReason.isEmpty)
                }
            }
            .navigationTitle("Report \(typeTitle)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var typeTitle: String {
        switch type {
        case .message: return "Message"
        case .room: return "Room"
        case .user: return "User"
        }
    }
}
