import SwiftUI

@main
struct ObdJeepApp: App {
    @StateObject private var viewModel = ObdDashboardViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .preferredColorScheme(.dark)
        }
    }
}
