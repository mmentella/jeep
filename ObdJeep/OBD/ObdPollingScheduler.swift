import Foundation

@MainActor
final class ObdPollingScheduler {
    private var task: Task<Void, Never>?

    var isRunning: Bool {
        task != nil
    }

    func start(
        client: Elm327Client,
        onReading: @escaping @MainActor (ObdReading) -> Void,
        onError: @escaping @MainActor (ObdPid, Error) -> Void
    ) {
        stop()
        task = Task { @MainActor in
            while !Task.isCancelled {
                for pid in ObdPid.allCases {
                    guard !Task.isCancelled else { return }
                    do {
                        let reading = try await client.read(pid)
                        onReading(reading)
                    } catch {
                        onError(pid, error)
                    }
                    try? await Task.sleep(nanoseconds: 120_000_000)
                }
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
