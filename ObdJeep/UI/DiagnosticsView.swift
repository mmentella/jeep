import SwiftUI

struct DiagnosticsView: View {
    let logs: [DiagnosticLogEntry]
    let onClear: () -> Void

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        NavigationStack {
            List {
                ForEach(logs.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(entry.direction.rawValue)
                                .font(.caption.monospaced().weight(.bold))
                                .foregroundStyle(color(for: entry.direction))
                            Text(Self.timeFormatter.string(from: entry.date))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.message)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .listRowBackground(Color.white.opacity(0.04))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.04, green: 0.05, blue: 0.06))
            .navigationTitle("Log ELM327")
            .toolbar {
                Button(action: onClear) {
                    Label("Pulisci", systemImage: "trash")
                }
            }
        }
    }

    private func color(for direction: DiagnosticLogEntry.Direction) -> Color {
        switch direction {
        case .outgoing: return .cyan
        case .incoming: return .mint
        case .info: return .secondary
        case .error: return .red
        }
    }
}
