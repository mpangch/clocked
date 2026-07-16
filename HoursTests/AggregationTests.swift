import XCTest
@testable import Hours

// Day/week/biweek/month aggregation and the weekly-goal line.
// Anchor "today" = Wednesday 2026-07-15; monday(today) = 2026-07-13.
final class AggregationTests: XCTestCase {

    func testRangeTotalsCountsOnlyDaysWithWork() {
        let sessions = [
            workSession(date(2026, 7, 13, 9, 0), date(2026, 7, 13, 12, 0)),    // Mon 3h
            workSession(date(2026, 7, 13, 13, 0), date(2026, 7, 13, 15, 0)),   // Mon +2h, same day
            sessionWithBreak(date(2026, 7, 15, 10, 0), date(2026, 7, 15, 14, 30),
                             breakStart: date(2026, 7, 15, 12, 0),
                             breakEnd: date(2026, 7, 15, 12, 30)),              // Wed 4h + 30m brk
        ]
        let t = Engine.rangeTotals(from: date(2026, 7, 13), to: date(2026, 7, 20),
                                   sessions: sessions, at: date(2026, 7, 19, 12, 0), calendar: testCal)
        XCTAssertEqual(t.work, 9 * 3600)
        XCTAssertEqual(t.brk, 1800)
        XCTAssertEqual(t.daysWithWork, 2)   // Monday counted once despite two sessions
    }

    // Week starts Monday: a Sunday session belongs to the week whose Monday
    // precedes it, and a Monday session belongs to that same week.
    func testWeekWorkedMondayBoundaries() {
        let sunPrevWeek = workSession(date(2026, 7, 12, 9, 0), date(2026, 7, 12, 13, 0))  // Sun, 4h
        let mon = workSession(date(2026, 7, 13, 9, 0), date(2026, 7, 13, 11, 0))          // Mon, 2h
        let sunThisWeek = workSession(date(2026, 7, 19, 12, 0), date(2026, 7, 19, 15, 0)) // Sun, 3h
        let all = [sunPrevWeek, mon, sunThisWeek]

        // Week of Mon 7-13: Monday and the trailing Sunday 7-19, not Sunday 7-12.
        XCTAssertEqual(Engine.weekWorked(sessions: all, at: date(2026, 7, 19, 20, 0), calendar: testCal),
                       5 * 3600)
        // Sunday 7-12 belongs to the week of Monday 7-06.
        XCTAssertEqual(Engine.weekWorked(sessions: all, at: date(2026, 7, 12, 18, 0), calendar: testCal),
                       4 * 3600)
    }

    // Goal math live-updates: the open session's elapsed work at `at` counts.
    func testWeekWorkedIncludesLiveSession() {
        let history = workSession(date(2026, 7, 13, 9, 0), date(2026, 7, 13, 11, 0))  // 2h
        let live = openWorkSession(date(2026, 7, 15, 9, 0))
        let at = date(2026, 7, 15, 11, 30)                                            // live 2.5h so far
        XCTAssertEqual(Engine.weekWorked(sessions: [history, live], at: at, calendar: testCal),
                       4.5 * 3600)
    }

    func testPeriodRangesWeekAndBiweek() {
        let w0 = Engine.periodRange(mode: .week, offset: 0, today: anchorNoon, calendar: testCal)
        XCTAssertEqual(w0.from, date(2026, 7, 13))
        XCTAssertEqual(w0.to, date(2026, 7, 20))
        let w1 = Engine.periodRange(mode: .week, offset: -1, today: anchorNoon, calendar: testCal)
        XCTAssertEqual(w1.from, date(2026, 7, 6))
        XCTAssertEqual(w1.to, date(2026, 7, 13))

        // Biweek anchored at monday(today) − 7d, spanning last week + this week.
        let b0 = Engine.periodRange(mode: .biweek, offset: 0, today: anchorNoon, calendar: testCal)
        XCTAssertEqual(b0.from, date(2026, 7, 6))
        XCTAssertEqual(b0.to, date(2026, 7, 20))
        let b1 = Engine.periodRange(mode: .biweek, offset: -1, today: anchorNoon, calendar: testCal)
        XCTAssertEqual(b1.from, date(2026, 6, 22))
        XCTAssertEqual(b1.to, date(2026, 7, 6))
    }

    func testMonthPeriodRange() {
        let m0 = Engine.periodRange(mode: .month, offset: 0, today: anchorNoon, calendar: testCal)
        XCTAssertEqual(m0.from, date(2026, 7, 1))
        XCTAssertEqual(m0.to, date(2026, 8, 1))
        let m1 = Engine.periodRange(mode: .month, offset: -1, today: anchorNoon, calendar: testCal)
        XCTAssertEqual(m1.from, date(2026, 6, 1))
        XCTAssertEqual(m1.to, date(2026, 7, 1))
    }

    // A shift belongs to the calendar day of its clockIn — no midnight split.
    func testShiftStaysOnClockInDay() {
        let s = workSession(date(2026, 7, 10, 23, 30), date(2026, 7, 11, 1, 30))  // 2h across midnight
        let at = date(2026, 7, 12, 12, 0)
        let friday = Engine.dayTotals(on: date(2026, 7, 10), sessions: [s], at: at, calendar: testCal)
        XCTAssertEqual(friday.work, 2 * 3600)
        XCTAssertEqual(friday.sessionCount, 1)
        let saturday = Engine.dayTotals(on: date(2026, 7, 11), sessions: [s], at: at, calendar: testCal)
        XCTAssertEqual(saturday.work, 0)
        XCTAssertEqual(saturday.sessionCount, 0)
        let r = Engine.rangeTotals(from: date(2026, 7, 10), to: date(2026, 7, 13),
                                   sessions: [s], at: at, calendar: testCal)
        XCTAssertEqual(r.daysWithWork, 1)
    }

    func testGoalNeed() {
        // Under: 30h worked vs 32.5h goal → 2h 30m short.
        let under = Engine.goalNeed(worked: 30 * 3600, goal: 32.5 * 3600)
        XCTAssertEqual(under.text, "Need **2h 30m** more to hit goal")
        XCTAssertTrue(under.text.hasPrefix("Need "))
        XCTAssertFalse(under.met)
        // Over: 33h worked → +30m over.
        let over = Engine.goalNeed(worked: 33 * 3600, goal: 32.5 * 3600)
        XCTAssertEqual(over.text, "Goal met · **+30m** over")
        XCTAssertTrue(over.text.hasPrefix("Goal met · "))
        XCTAssertTrue(over.met)
        // Exactly on goal counts as met (JS: diff > 0 is the only "need" case).
        let exact = Engine.goalNeed(worked: 32.5 * 3600, goal: 32.5 * 3600)
        XCTAssertEqual(exact.text, "Goal met · **+0m** over")
        XCTAssertTrue(exact.met)
    }
}
