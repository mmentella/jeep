import XCTest
@testable import ObdJeep

final class ObdCommandPolicyTests: XCTestCase {
    func testAllowsStandardReadCommands() {
        XCTAssertEqual(ObdCommandPolicy.evaluate("010C"), .allowStandard)
        XCTAssertEqual(ObdCommandPolicy.evaluate("0902"), .allowStandard)
        XCTAssertEqual(ObdCommandPolicy.evaluate("ATRV"), .allowStandard)
    }

    func testWarnsForProprietaryReadService() {
        if case .warnNonStandard = ObdCommandPolicy.evaluate("22F190") {
            return
        }
        XCTFail("Expected warning for service 22")
    }

    func testBlocksWriteAndProgrammingServices() {
        if case .block = ObdCommandPolicy.evaluate("2EF1901234") {
            return
        }
        XCTFail("Expected block for service 2E")
    }

    func testBlocksSecurityAccess() {
        if case .block = ObdCommandPolicy.evaluate("2701") {
            return
        }
        XCTFail("Expected block for service 27")
    }
}
