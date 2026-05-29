import Foundation

enum Elm327CommandSource: String, Codable, Equatable {
    case initialization = "init"
    case polling
    case manual
    case diagnostic
}

struct Elm327Command: Equatable {
    let command: String
    let timeout: TimeInterval
    let expectedResponsePrefix: String?
    let source: Elm327CommandSource

    init(
        command: String,
        timeout: TimeInterval = 4.0,
        expectedResponsePrefix: String? = nil,
        source: Elm327CommandSource
    ) {
        self.command = ObdCommandPolicy.normalize(command)
        self.timeout = timeout
        self.expectedResponsePrefix = expectedResponsePrefix?.uppercased()
        self.source = source
    }
}
