import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct PidLabJSONExport: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { export in
            export.data
        }
    }
}

struct PidLabCSVExport: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { export in
            export.data
        }
    }
}
