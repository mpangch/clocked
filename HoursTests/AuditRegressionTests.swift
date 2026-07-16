import XCTest
@testable import Hours

/// Regressions for confirmed fidelity-audit findings.
final class AuditRegressionTests: XCTestCase {

    /// engine-core-1: JS toFixed(1) rounds decimal ties up — 4.25h must format
    /// as "4.3h" (printf %.1f would give the half-to-even "4.2").
    func testH1RoundsTiesUpLikeToFixed() {
        XCTAssertEqual(Fmt.h1(4.25 * 3600), "4.3h")
        XCTAssertEqual(Fmt.h1(1.25 * 3600), "1.3h")
        XCTAssertEqual(Fmt.h1(2.25 * 3600), "2.3h")
        // Non-tie values unchanged
        XCTAssertEqual(Fmt.h1(7 * 3600), "7h")
        XCTAssertEqual(Fmt.h1(6.8 * 3600), "6.8h")
        XCTAssertEqual(Fmt.h1(0), "0h")
    }

    /// track-ui-1: mockup's setRing clamps net/planned to [0,1]; planned == 0
    /// with any net worked yields Infinity → clamps to a FULL ring, not empty.
    func testRingProgressZeroPlan() {
        XCTAssertEqual(Engine.ringProgress(netWorked: 1, plannedWork: 0), 1)
        XCTAssertEqual(Engine.ringProgress(netWorked: 0, plannedWork: 0), 0)
        XCTAssertEqual(Engine.ringProgress(netWorked: 3600, plannedWork: 7200), 0.5)
        XCTAssertEqual(Engine.ringProgress(netWorked: 9000, plannedWork: 7200), 1)
    }
}
