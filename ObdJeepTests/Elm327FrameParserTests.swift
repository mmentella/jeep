import XCTest
@testable import ObdJeep

final class Elm327FrameParserTests: XCTestCase {
    func testParsesOkResponse() throws {
        let command = Elm327Command(command: "ATE0", expectedResponsePrefix: "OK", source: .initialization)
        let response = try Elm327FrameParser.parse(rawText: "OK\r>", command: command)

        XCTAssertTrue(response.isOK)
        XCTAssertTrue(response.promptSeen)
        XCTAssertEqual(response.lines, ["OK"])
    }

    func testParsesSearchingThenFrame() throws {
        let command = Elm327Command(command: "010C", expectedResponsePrefix: "410C", source: .polling)
        let response = try Elm327FrameParser.parse(rawText: "SEARCHING...\r41 0C 0F A0\r>", command: command)

        XCTAssertEqual(response.frames.first?.bytes, [0x41, 0x0C, 0x0F, 0xA0])
    }

    func testParsesFrameWithCanHeader() throws {
        let command = Elm327Command(command: "0105", expectedResponsePrefix: "4105", source: .polling)
        let response = try Elm327FrameParser.parse(rawText: "7E8 03 41 05 5A\r>", command: command)

        XCTAssertEqual(response.frames.first?.header, "7E8")
        XCTAssertEqual(response.frames.first?.bytes, [0x03, 0x41, 0x05, 0x5A])
    }

    func testThrowsTypedAdapterErrors() {
        let command = Elm327Command(command: "010C", source: .polling)

        XCTAssertThrowsError(try Elm327FrameParser.parse(rawText: "NO DATA\r>", command: command)) { error in
            XCTAssertEqual(error as? Elm327Error, .noData(raw: "NO DATA\r>"))
        }
        XCTAssertThrowsError(try Elm327FrameParser.parse(rawText: "STOPPED\r>", command: command)) { error in
            XCTAssertEqual(error as? Elm327Error, .stopped(raw: "STOPPED\r>"))
        }
        XCTAssertThrowsError(try Elm327FrameParser.parse(rawText: "BUS ERROR\r>", command: command)) { error in
            XCTAssertEqual(error as? Elm327Error, .busError(raw: "BUS ERROR\r>"))
        }
        XCTAssertThrowsError(try Elm327FrameParser.parse(rawText: "CAN ERROR\r>", command: command)) { error in
            XCTAssertEqual(error as? Elm327Error, .canError(raw: "CAN ERROR\r>"))
        }
        XCTAssertThrowsError(try Elm327FrameParser.parse(rawText: "UNABLE TO CONNECT\r>", command: command)) { error in
            XCTAssertEqual(error as? Elm327Error, .unableToConnect(raw: "UNABLE TO CONNECT\r>"))
        }
    }

    func testThrowsMalformedFrame() {
        let command = Elm327Command(command: "010C", source: .polling)
        XCTAssertThrowsError(try Elm327FrameParser.parse(rawText: "7E8 Z1\r>", command: command)) { error in
            XCTAssertEqual(error as? Elm327Error, .malformedFrame(raw: "7E8 Z1\r>"))
        }
    }

    func testThrowsNegativeResponseInsideCanFrame() {
        let command = Elm327Command(command: "22F190", source: .manual)
        XCTAssertThrowsError(try Elm327FrameParser.parse(rawText: "7E8 03 7F 22 31\r>", command: command)) { error in
            XCTAssertEqual(error as? Elm327Error, .negativeResponse(service: "22", code: "31", raw: "7E8 03 7F 22 31\r>"))
        }
    }
}
