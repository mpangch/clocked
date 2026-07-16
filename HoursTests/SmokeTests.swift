import XCTest
@testable import Hours

final class SmokeTests: XCTestCase {
    func testFormattersSmoke() {
        XCTAssertEqual(Fmt.dur(7 * 3600 + 5 * 60), "7h 5m")
        XCTAssertEqual(Fmt.hm(420), "7h 00m")
        XCTAssertEqual(Fmt.timer(3661), "1:01:01")
    }
}
