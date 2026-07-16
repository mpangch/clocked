import XCTest
@testable import Clocked

// Session/segment arithmetic — mockup: segMs / sumSegs / dayTotals / state.
// All expected values derived by hand from the mockup JS.
final class SegmentMathTests: XCTestCase {

    // Open segments are measured up to `at`; never negative.
    func testOpenSegmentSums() {
        let live = openWorkSession(date(2026, 7, 15, 9, 0))
        let at = date(2026, 7, 15, 11, 30)
        XCTAssertEqual(Engine.workDuration(live, at: at), 2.5 * 3600)   // 9:00 → 11:30
        XCTAssertEqual(Engine.breakDuration(live, at: at), 0)
        // `at` before the segment start clamps to 0 (JS: Math.max(0, …))
        XCTAssertEqual(Engine.workDuration(live, at: date(2026, 7, 15, 8, 0)), 0)

        let onBreak = openBreakSession(date(2026, 7, 15, 9, 0), breakStart: date(2026, 7, 15, 12, 0))
        let at2 = date(2026, 7, 15, 12, 20)
        XCTAssertEqual(Engine.workDuration(onBreak, at: at2), 3 * 3600)  // 9:00–12:00
        XCTAssertEqual(Engine.breakDuration(onBreak, at: at2), 20 * 60)  // 12:00 → at
        XCTAssertEqual(Engine.breakCount(onBreak), 1)                    // open break counts
    }

    func testClosedSessionSumsAndBreakCount() {
        // 9:00–17:00 with breaks 12:00–13:00 and 15:00–15:30 → net 6.5h, break 1.5h
        let s = session(date(2026, 7, 14, 9, 0), date(2026, 7, 14, 17, 0),
                        breaks: [(date(2026, 7, 14, 12, 0), date(2026, 7, 14, 13, 0)),
                                 (date(2026, 7, 14, 15, 0), date(2026, 7, 14, 15, 30))])
        let at = date(2026, 7, 15, 12, 0) // irrelevant for closed segments
        XCTAssertEqual(Engine.workDuration(s, at: at), 6.5 * 3600)
        XCTAssertEqual(Engine.breakDuration(s, at: at), 1.5 * 3600)
        XCTAssertEqual(Engine.breakCount(s), 2)
    }

    func testDayTotalsMultipleSessionsPerDay() {
        let s1 = workSession(date(2026, 7, 14, 9, 0), date(2026, 7, 14, 12, 0))            // 3h
        let s2 = sessionWithBreak(date(2026, 7, 14, 13, 0), date(2026, 7, 14, 17, 30),
                                  breakStart: date(2026, 7, 14, 15, 0),
                                  breakEnd: date(2026, 7, 14, 15, 30))                     // 4h + 30m brk
        let otherDay = workSession(date(2026, 7, 13, 9, 0), date(2026, 7, 13, 10, 0))      // excluded
        let t = Engine.dayTotals(on: date(2026, 7, 14), sessions: [s1, s2, otherDay],
                                 at: date(2026, 7, 15, 12, 0), calendar: testCal)
        XCTAssertEqual(t.work, 7 * 3600)
        XCTAssertEqual(t.brk, 1800)
        XCTAssertEqual(t.sessionCount, 2)
        XCTAssertEqual(t.first, date(2026, 7, 14, 9, 0))
        XCTAssertEqual(t.last, date(2026, 7, 14, 17, 30))
    }

    // mockup dayTotals: for the live session `end = s.out || at`, so last == at.
    func testDayTotalsLiveSessionLastEqualsAt() {
        let live = openWorkSession(date(2026, 7, 15, 9, 0))
        let at = date(2026, 7, 15, 11, 47)
        let t = Engine.dayTotals(on: date(2026, 7, 15), sessions: [live], at: at, calendar: testCal)
        XCTAssertEqual(t.first, date(2026, 7, 15, 9, 0))
        XCTAssertEqual(t.last, at)
        XCTAssertEqual(t.work, 2 * 3600 + 47 * 60)
        XCTAssertEqual(t.sessionCount, 1)
    }

    func testTrackState() {
        XCTAssertEqual(Engine.state(live: nil), TrackState.out)
        XCTAssertEqual(Engine.state(live: openWorkSession(anchorNoon)), .working)
        XCTAssertEqual(Engine.state(live: openBreakSession(date(2026, 7, 15, 9, 0),
                                                           breakStart: anchorNoon)), .onBreak)
    }
}
