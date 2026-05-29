import XCTest
@testable import ObdJeep

final class ObdValueParserTests: XCTestCase {
    func testParsesStandardPids() throws {
        XCTAssertEqual(try ObdValueParser.parse(rawResponse: "41 0C 1A F8", pid: .rpm), 1726)
        XCTAssertEqual(try ObdValueParser.parse(rawResponse: "41 0D 3E", pid: .speed), 62)
        XCTAssertEqual(try ObdValueParser.parse(rawResponse: "41 05 5F", pid: .coolantTemperature), 55)
        XCTAssertEqual(try ObdValueParser.parse(rawResponse: "41 42 31 10", pid: .controlModuleVoltage), 12.56, accuracy: 0.001)
        XCTAssertEqual(try ObdValueParser.parse(rawResponse: "41 04 80", pid: .engineLoad), 50.196, accuracy: 0.001)
        XCTAssertEqual(try ObdValueParser.parse(rawResponse: "41 11 40", pid: .throttlePosition), 25.098, accuracy: 0.001)
    }

    func testIgnoresElmNoiseAndPrompt() throws {
        let raw = "SEARCHING...\r\n41 0C 0F A0\r\n>"
        XCTAssertEqual(try ObdValueParser.parse(rawResponse: raw, pid: .rpm), 1000)
    }

    func testParsesCompactResponses() throws {
        XCTAssertEqual(try ObdValueParser.parse(rawResponse: "410D2A>", pid: .speed), 42)
    }

    func testParsesResponseWithCanHeaderPrefix() throws {
        XCTAssertEqual(try ObdValueParser.parse(rawResponse: "7E8 03 41 05 5A", pid: .coolantTemperature), 50)
    }

    func testRejectsNoData() {
        XCTAssertThrowsError(try ObdValueParser.parse(rawResponse: "NO DATA", pid: .speed))
    }

    func testRejectsPidMismatch() {
        XCTAssertThrowsError(try ObdValueParser.parse(rawResponse: "41 0D 20", pid: .rpm))
    }
}
