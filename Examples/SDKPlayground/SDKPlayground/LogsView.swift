//
//  LogsView.swift
//  SDKPlayground
//

import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var logs: PlaygroundLogStore
    @State private var filterText: String = ""

    var body: some View {
        NavigationView {
            List {
                Section {
                    TextField("Filter logs (text or level: info/error/...)", text: $filterText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                ForEach(filteredLines) { line in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(line.date, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(line.message)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(color(for: line.level))
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
            }
            .navigationTitle("Logs")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") {
                        logs.clear()
                    }
                }
            }
        }
    }
    
    private var filteredLines: [PlaygroundLogStore.LogLine] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return logs.lines }
        return logs.lines.filter { line in
            line.message.lowercased().contains(query) ||
            line.level.rawValue.lowercased().contains(query)
        }
    }

    private func color(for level: PlaygroundLogStore.LogLine.Level) -> Color {
        switch level {
        case .info: return .primary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}
