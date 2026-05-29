import SwiftUI

struct PidLabView: View {
    @ObservedObject var viewModel: ObdDashboardViewModel
    @State private var command = "010C"
    @State private var pendingCommand = ""
    @State private var pendingWarning = ""
    @State private var showingWarning = false

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    safetyPanel
                    commandPanel
                    exportPanel
                    logPanel
                    placeholderPanel
                }
                .padding()
            }
            .background(Color(red: 0.04, green: 0.05, blue: 0.06))
            .navigationTitle("PID Lab")
            .alert("Comando non standard", isPresented: $showingWarning) {
                Button("Annulla", role: .cancel) {}
                Button("Invia lettura") {
                    Task {
                        await viewModel.sendPidLabCommand(pendingCommand, warning: pendingWarning)
                    }
                }
            } message: {
                Text(pendingWarning)
            }
        }
    }

    private var safetyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Read-only", systemImage: "lock.shield")
                .font(.headline)
            Text("Il Lab consente solo letture OBD/ELM327. Servizi di scrittura, reset, security access, routine control e codifica ECU sono bloccati.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(viewModel.pidLabStatus)
                .font(.caption.monospaced())
                .foregroundStyle(.mint)
        }
        .padding(14)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private var commandPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comando manuale")
                .font(.headline)
            HStack(spacing: 10) {
                TextField("010C", text: $command)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .padding(10)
                    .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
                Button {
                    submit()
                } label: {
                    Label("Invia", systemImage: "paperplane")
                }
                .buttonStyle(.borderedProminent)
                .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack {
                quickCommand("RPM", "010C")
                quickCommand("VIN", "0902")
                quickCommand("Voltage", "ATRV")
                quickCommand("22 read", "22F190")
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private var exportPanel: some View {
        HStack {
            ShareLink(item: viewModel.pidLabCSVExport, preview: SharePreview("pid-lab-log.csv")) {
                Label("CSV", systemImage: "tablecells")
            }
            .buttonStyle(.bordered)
            ShareLink(item: viewModel.pidLabJSONExport, preview: SharePreview("pid-lab-log.json")) {
                Label("JSON", systemImage: "curlybraces")
            }
            .buttonStyle(.bordered)
            Spacer()
            Button(role: .destructive) {
                viewModel.clearPidLabLogs()
            } label: {
                Label("Pulisci", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Raw responses")
                .font(.headline)
            if viewModel.pidLabLogs.isEmpty {
                Text("Nessuna risposta registrata.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.pidLabLogs) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(Self.timeFormatter.string(from: entry.date))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(entry.adapterMode)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if !entry.isStandardRead {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text("TX \(entry.command)")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(.cyan)
                        Text("RX \(entry.response)")
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(10)
                    .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private var placeholderPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Categorie future")
                .font(.headline)
            ForEach(CustomPidCatalog.placeholders) { pid in
                HStack {
                    Text(pid.category.title)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(pid.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private func quickCommand(_ title: String, _ value: String) -> some View {
        Button {
            command = value
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
    }

    private func submit() {
        let normalized = ObdCommandPolicy.normalize(command)
        switch viewModel.commandDecision(for: normalized) {
        case .allowStandard:
            Task {
                await viewModel.sendPidLabCommand(normalized, warning: nil)
            }
        case .warnNonStandard(let warning):
            pendingCommand = normalized
            pendingWarning = warning
            showingWarning = true
        case .block(let reason):
            viewModel.pidLabStatus = reason
        }
    }
}
