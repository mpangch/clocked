import XCTest
@testable import Clocked

// ETA text, planned-work fallback chain, ring progress, pro-rated period
// goals, and the Fmt formatter ports.
final class EtaAndGoalTests: XCTestCase {

    func testEtaText() {
        // 2h remaining at 2:00 PM → done ~4:00 PM.
        XCTAssertEqual(Engine.etaText(plannedWork: 7 * 3600, netWorked: 5 * 3600,
                                      at: date(2026, 7, 15, 14, 0), calendar: testCal),
                       "done ~4:00 PM")
        // remain == 0 and remain < 0 both read "complete" (JS: remain > 0 gate).
        XCTAssertEqual(Engine.etaText(plannedWork: 7 * 3600, netWorked: 7 * 3600,
                                      at: date(2026, 7, 15, 16, 0), calendar: testCal),
                       "planned hours complete")
        XCTAssertEqual(Engine.etaText(plannedWork: 7 * 3600, netWorked: 8 * 3600,
                                      at: date(2026, 7, 15, 17, 0), calendar: testCal),
                       "planned hours complete")
    }

    // plannedWorkMs: explicit plan → learned weekday average → 7h fallback.
    func testPlannedWorkDurationFallbackChain() {
        XCTAssertEqual(Engine.plannedWorkDuration(planWorkMin: 400, stats: makeStats(avgNetMin: 380)),
                       400 * 60)
        XCTAssertEqual(Engine.plannedWorkDuration(planWorkMin: nil, stats: makeStats(avgNetMin: 380)),
                       380 * 60)
        XCTAssertEqual(Engine.plannedWorkDuration(planWorkMin: nil, stats: nil), 420 * 60)
    }

    func testRingProgressClamps() {
        XCTAssertEqual(Engine.ringProgress(netWorked: 2 * 3600, plannedWork: 8 * 3600), 0.25)
        XCTAssertEqual(Engine.ringProgress(netWorked: 9 * 3600, plannedWork: 8 * 3600), 1.0)
        XCTAssertEqual(Engine.ringProgress(netWorked: -60, plannedWork: 3600), 0)
        // mockup: net/0 → Infinity → clamped to a full ring once any net exists
        XCTAssertEqual(Engine.ringProgress(netWorked: 3600, plannedWork: 0), 1)
    }

    func testPeriodGoalWeekAndBiweek() {
        let g = 32.5 * 60   // 1950 minutes
        let w = Engine.periodRange(mode: .week, offset: 0, today: anchorNoon, calendar: testCal)
        XCTAssertEqual(Engine.periodGoal(mode: .week, from: w.from, to: w.to, goalMinutes: g),
                       117_000)                       // 1950 × 60 s
        let b = Engine.periodRange(mode: .biweek, offset: 0, today: anchorNoon, calendar: testCal)
        XCTAssertEqual(Engine.periodGoal(mode: .biweek, from: b.from, to: b.to, goalMinutes: g),
                       234_000)
    }

    // Month goal pro-rated: G × daysInMonth / 7.
    func testPeriodGoalMonthProRated() {
        let g = 32.5 * 60
        // July 2026 has 31 days.
        let july = Engine.periodGoal(mode: .month, from: date(2026, 7, 1), to: date(2026, 8, 1), goalMinutes: g)
        XCTAssertEqual(july, 1950.0 * 60 * 31 / 7, accuracy: 0.001)
        // February 2026 (28 days) is exactly four weeks' goal.
        let feb = Engine.periodGoal(mode: .month, from: date(2026, 2, 1), to: date(2026, 3, 1), goalMinutes: g)
        XCTAssertEqual(feb, 4 * 117_000, accuracy: 0.001)
    }

    func testDurationAndHMFormatters() {
        XCTAssertEqual(Fmt.dur(90), "2m")             // rounds to nearest minute
        XCTAssertEqual(Fmt.dur(89), "1m")
        XCTAssertEqual(Fmt.dur(3570), "1h 0m")        // 59.5m rounds up to 60
        XCTAssertEqual(Fmt.dur(7 * 3600 + 5 * 60), "7h 5m")
        XCTAssertEqual(Fmt.dur(-5), "0m")             // clamps at 0
        XCTAssertEqual(Fmt.hm(420), "7h 00m")         // zero-pads minutes
        XCTAssertEqual(Fmt.hm(65), "1h 05m")
    }

    func testTimerAndH1Formatters() {
        XCTAssertEqual(Fmt.timer(3661), "1:01:01")
        XCTAssertEqual(Fmt.timer(3661.9), "1:01:01")  // floors seconds
        XCTAssertEqual(Fmt.timer(59), "0:00:59")
        XCTAssertEqual(Fmt.timer(-3), "0:00:00")
        XCTAssertEqual(Fmt.h1(7 * 3600), "7h")        // strips ".0"
        XCTAssertEqual(Fmt.h1(6.8 * 3600), "6.8h")
    }

    func testGoalHoursAndMinToClock() {
        XCTAssertEqual(Fmt.goalHours(32.5), "32.5h")
        XCTAssertEqual(Fmt.goalHours(32.0), "32h")
        XCTAssertEqual(Fmt.minToClock(0), "12:00 AM")
        XCTAssertEqual(Fmt.minToClock(720), "12:00 PM")
        XCTAssertEqual(Fmt.minToClock(840), "2:00 PM")
    }
}
