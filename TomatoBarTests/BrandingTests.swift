import XCTest
@testable import TomatoBar

final class BrandingTests: XCTestCase {
    func testTomaTraceURLSchemeParsesStartStopCaseInsensitively() {
        XCTAssertEqual(
            TomaTraceURLCommand(
                url: URL(string: "TOMATRACE://startStop")!
            ),
            .startStop
        )
    }

    func testLegacyOrUnknownURLsAreRejected() {
        XCTAssertNil(
            TomaTraceURLCommand(
                url: URL(string: "tomatobar://startStop")!
            )
        )
        XCTAssertNil(
            TomaTraceURLCommand(
                url: URL(string: "tomatrace://unknown")!
            )
        )
    }
}
