import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: ObdDashboardViewModel

    var body: some View {
        TabView {
            DashboardView(viewModel: viewModel)
                .tabItem {
                    Label("Live", systemImage: "gauge.with.dots.needle.33percent")
                }
            DiagnosticsView(logs: viewModel.logs, onClear: viewModel.clearLogs)
                .tabItem {
                    Label("Diagnostica", systemImage: "terminal")
                }
            PidLabView(viewModel: viewModel)
                .tabItem {
                    Label("PID Lab", systemImage: "testtube.2")
                }
        }
        .tint(.mint)
        .onAppear {
            if viewModel.peripherals.isEmpty {
                viewModel.configureTransport()
                viewModel.startScan()
            }
        }
    }
}
