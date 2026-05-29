import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: ObdDashboardViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 158), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    connectionPanel
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(ObdPid.allCases) { pid in
                            GaugeCard(pid: pid, reading: viewModel.readings[pid])
                        }
                    }
                }
                .padding()
            }
            .background(Color(red: 0.04, green: 0.05, blue: 0.06))
            .navigationTitle("OBD Jeep")
        }
    }

    private var connectionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.isConnected ? "Connesso" : "Scanner")
                        .font(.headline)
                    Text(viewModel.status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Picker("Modalita adattatore", selection: Binding(
                get: { viewModel.adapterMode },
                set: { viewModel.selectMode($0) }
            )) {
                ForEach(ObdDashboardViewModel.AdapterMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if viewModel.isConnected {
                Button(role: .destructive) {
                    viewModel.disconnect()
                } label: {
                    Label("Disconnetti", systemImage: "bolt.horizontal.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                HStack {
                    Button {
                        viewModel.startScan()
                    } label: {
                        Label("Cerca", systemImage: "dot.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    if let first = viewModel.peripherals.first {
                        Button {
                            viewModel.connect(to: first)
                        } label: {
                            Label("Connetti", systemImage: "link")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                ForEach(viewModel.peripherals) { peripheral in
                    Button {
                        viewModel.connect(to: peripheral)
                    } label: {
                        HStack {
                            Image(systemName: "wave.3.right.circle")
                            VStack(alignment: .leading) {
                                Text(peripheral.name)
                                    .font(.subheadline.weight(.semibold))
                                Text("RSSI \(peripheral.rssi)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}
