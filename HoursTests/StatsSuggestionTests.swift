import XCTest
@testable import Hours

// Learned per-weekday stats (mockup: statsFor), suggestion text, plan-draft
// fill, break nudge window, and the forgot-to-clock-out banner.
// Reference "today" = Wednesday 2026-07-15 noon; 8-week window starts 2026-05-20.
final class StatsSuggestionTests: XCTestCase {

    // Two Tuesdays:
    //  A 2026-07-07 9:00–16:00, break 12:00–12:55 → net 365m, brk 55m, start 540
    //  B 2026-07-14 9:30–16:30, break 13:00–13:45 → net 375m, brk 45m, start 570
    func testStatsAverages() {
        let a = sessionWithBreak(date(2026, 7, 7, 9, 0), date(2026, 7, 7, 16, 0),
                                 breakStart: date(2026, 7, 7, 12, 0), breakEnd: date(2026, 7, 7, 12, 55))
        let b = sessionWithBreak(date(2026, 7, 14, 9, 30), date(2026, 7, 14, 16, 30),
                                 breakStart: date(2026, 7, 14, 13, 0), breakEnd: date(2026, 7, 14, 13, 45))
        let st = Engine.stats(forWeekday: 2, history: [a, b], reference: anchorNoon, calendar: testCal)
        XCTAssertNotNil(st)
        XCTAssertEqual(st?.n, 2)
        XCTAssertEqual(st?.avgNetMin, 370)          // (365 + 375) / 2
        XCTAssertEqual(st?.avgBreakMin, 50)         // (55 + 45) / 2
        XCTAssertEqual(st?.breakFreq, 1.0)          // 2 break segments / 2 shifts
        XCTAssertEqual(st?.breakCount, 1)
        XCTAssertEqual(st?.avgStartMin, 555)        // (540 + 570) / 2
        XCTAssertEqual(st?.typBreakStartMin, 750)   // (720 + 780) / 2
        XCTAssertEqual(st?.typBreakDurMin, 50)      // round(50 / max(1, 1))
    }

    // typBreakStartMin averages FIRST-break starts, only over sessions that
    // have breaks; sessions without breaks don't dilute it.
    func testTypBreakStartUsesFirstBreaksOnly() {
        let a = session(date(2026, 7, 7, 9, 0), date(2026, 7, 7, 17, 0),
                        breaks: [(date(2026, 7, 7, 12, 0), date(2026, 7, 7, 12, 30)),
                                 (date(2026, 7, 7, 15, 0), date(2026, 7, 7, 15, 15))])   // first at 720
        let b = sessionWithBreak(date(2026, 7, 14, 9, 0), date(2026, 7, 14, 16, 0),
                                 breakStart: date(2026, 7, 14, 13, 0), breakEnd: date(2026, 7, 14, 13, 30)) // 780
        let c = workSession(date(2026, 6, 30, 9, 0), date(2026, 6, 30, 16, 0))           // no breaks
        let st = Engine.stats(forWeekday: 2, history: [a, b, c], reference: anchorNoon, calendar: testCal)
        XCTAssertEqual(st?.typBreakStartMin, 750)   // (720 + 780) / 2 — c excluded
        XCTAssertEqual(st?.breakFreq, 1.0)          // 3 segments / 3 shifts
        XCTAssertEqual(st?.breakCount, 1)
        // No breaks at all → typBreakStartMin nil, typBreakDurMin 0.
        let none = Engine.stats(forWeekday: 2, history: [c], reference: anchorNoon, calendar: testCal)
        XCTAssertNil(none?.typBreakStartMin)
        XCTAssertEqual(none?.typBreakDurMin, 0)
    }

    // JS: typBreakDurMin = Math.round(brkMs/n/60000 / Math.max(1, Math.round(cnt/n)))
    // Two Thursdays with 2 breaks each: brk 60m + 30m → avg 45m, count 2 → round(22.5) = 23.
    func testTypBreakDurWithMultipleBreaksPerShift() {
        let a = session(date(2026, 7, 9, 9, 0), date(2026, 7, 9, 17, 0),
                        breaks: [(date(2026, 7, 9, 11, 0), date(2026, 7, 9, 11, 30)),
                                 (date(2026, 7, 9, 14, 0), date(2026, 7, 9, 14, 30))])
        let b = session(date(2026, 7, 2, 9, 0), date(2026, 7, 2, 17, 0),
                        breaks: [(date(2026, 7, 2, 11, 0), date(2026, 7, 2, 11, 15)),
                                 (date(2026, 7, 2, 14, 0), date(2026, 7, 2, 14, 15))])
        let st = Engine.stats(forWeekday: 4, history: [a, b], reference: anchorNoon, calendar: testCal)
        XCTAssertEqual(st?.breakCount, 2)           // round(4 / 2)
        XCTAssertEqual(st?.breakFreq, 2.0)
        XCTAssertEqual(st?.avgBreakMin, 45)         // (60 + 30) / 2
        XCTAssertEqual(st?.typBreakDurMin, 23)      // round(45 / 2) = round(22.5)
        XCTAssertEqual(st?.typBreakStartMin, 660)   // both first breaks at 11:00
    }

    // Rolling 8-week window (window start = startOfDay(reference) − 56d = 2026-05-20).
    func testEightWeekWindowEdges() {
        // 57 days before reference (Tue 2026-05-19) → excluded → no stats at all.
        let tooOld = workSession(date(2026, 5, 19, 9, 0), date(2026, 5, 19, 16, 0))
        XCTAssertNil(Engine.stats(forWeekday: 2, history: [tooOld], reference: anchorNoon, calendar: testCal))
        // 55 days before reference (Thu 2026-05-21) → included.
        let recentEnough = workSession(date(2026, 5, 21, 9, 0), date(2026, 5, 21, 16, 0))
        let st = Engine.stats(forWeekday: 4, history: [recentEnough], reference: anchorNoon, calendar: testCal)
        XCTAssertEqual(st?.n, 1)
        XCTAssertEqual(st?.avgNetMin, 420)
        // Exactly 56 days before (Wed 2026-05-20, clockIn 9:00 ≥ window start midnight) → included.
        let boundary = workSession(date(2026, 5, 20, 9, 0), date(2026, 5, 20, 16, 0))
        XCTAssertEqual(Engine.stats(forWeekday: 3, history: [boundary], reference: anchorNoon, calendar: testCal)?.n, 1)
    }

    // Weekday uses the JS getDay() convention: 0 = Sunday … 6 = Saturday.
    func testWeekdayFilterUsesJSConvention() {
        let sunday = workSession(date(2026, 7, 12, 10, 0), date(2026, 7, 12, 14, 0))
        XCTAssertEqual(Engine.stats(forWeekday: 0, history: [sunday], reference: anchorNoon, calendar: testCal)?.avgNetMin,
                       240)
        XCTAssertNil(Engine.stats(forWeekday: 1, history: [sunday], reference: anchorNoon, calendar: testCal))
    }

    func testSuggestionTextSingleBreak() {
        let st = makeStats(avgNetMin: 405, avgBreakMin: 55, breakCount: 1, breakFreq: 1.0,
                           typBreakStartMin: 840, typBreakDurMin: 55)
        XCTAssertEqual(Engine.suggestionText(st, weekday: 2),
                       "Tuesdays you usually work **6h 45m**, with a ~**55m** break around **2:00 PM**.")
    }

    func testSuggestionTextVariants() {
        // breakCount ≥ 2 uses the number; avgNetMin 367 → round5 → 365 ("6h 05m"),
        // typBreakDurMin 23 → round5 → 25.
        let two = makeStats(avgNetMin: 367, breakCount: 2, breakFreq: 2.0,
                            typBreakStartMin: 750, typBreakDurMin: 23)
        XCTAssertEqual(Engine.suggestionText(two, weekday: 4),
                       "Thursdays you usually work **6h 05m**, with 2 ~**25m** break around **12:30 PM**.")
        // "usually without breaks" ONLY when no break info AND breakFreq < 0.3.
        let rare = makeStats(avgNetMin: 420, breakCount: 0, breakFreq: 0.2,
                             typBreakStartMin: nil, typBreakDurMin: 0)
        XCTAssertEqual(Engine.suggestionText(rare, weekday: 1),
                       "Mondays you usually work **7h 00m**, usually without breaks.")
        // No break info but breakFreq ≥ 0.3 → plain base + ".".
        let sometimes = makeStats(avgNetMin: 390, breakCount: 0, breakFreq: 0.4,
                                  typBreakStartMin: nil, typBreakDurMin: 0)
        XCTAssertEqual(Engine.suggestionText(sometimes, weekday: 5),
                       "Fridays you usually work **6h 30m**.")
        XCTAssertNil(Engine.suggestionText(nil, weekday: 2))
    }

    func testPlanDraftFromStats() {
        // round5 on both fields: 367 → 365, 52 → 50.
        let st = makeStats(avgNetMin: 367, avgBreakMin: 52, breakCount: 1)
        XCTAssertEqual(Engine.planDraft(from: st), PlanDraft(workMin: 365, breakCount: 1, breakMin: 50))
        // breakCount 0 zeroes breakMin even when avgBreakMin > 0.
        let noBreaks = makeStats(avgNetMin: 420, avgBreakMin: 47, breakCount: 0, breakFreq: 0.1,
                                 typBreakStartMin: nil, typBreakDurMin: 0)
        XCTAssertEqual(Engine.planDraft(from: noBreaks), PlanDraft(workMin: 420, breakCount: 0, breakMin: 0))
    }

    // Window is [typ − 20, typ + 45] inclusive; typ = 840 (2:00 PM).
    func testNudgeWindowEdges() {
        let st = makeStats(breakFreq: 1.0, typBreakStartMin: 840)
        func nudge(atMinute h: Int, _ m: Int) -> Bool {
            Engine.shouldShowBreakNudge(stats: st, state: .working, nudgeDismissed: false,
                                        liveBreakCount: 0, at: date(2026, 7, 15, h, m), calendar: testCal)
        }
        XCTAssertTrue(nudge(atMinute: 13, 40))    // typ − 20
        XCTAssertFalse(nudge(atMinute: 13, 39))   // typ − 21
        XCTAssertTrue(nudge(atMinute: 14, 45))    // typ + 45
        XCTAssertFalse(nudge(atMinute: 14, 46))   // typ + 46
    }

    func testNudgeGatingConditions() {
        let at = date(2026, 7, 15, 14, 0)   // exactly typical break start
        func nudge(stats: WeekdayStats?, state: TrackState = .working,
                   dismissed: Bool = false, liveBreaks: Int = 0) -> Bool {
            Engine.shouldShowBreakNudge(stats: stats, state: state, nudgeDismissed: dismissed,
                                        liveBreakCount: liveBreaks, at: at, calendar: testCal)
        }
        XCTAssertFalse(nudge(stats: makeStats(breakFreq: 0.49)))                  // freq just below
        XCTAssertTrue(nudge(stats: makeStats(breakFreq: 0.5)))                    // freq at threshold
        XCTAssertFalse(nudge(stats: makeStats(), liveBreaks: 1))                  // already took a break
        XCTAssertFalse(nudge(stats: makeStats(), state: .onBreak))
        XCTAssertFalse(nudge(stats: makeStats(), state: .out))
        XCTAssertFalse(nudge(stats: makeStats(), dismissed: true))
        XCTAssertFalse(nudge(stats: nil))
        XCTAssertFalse(nudge(stats: makeStats(typBreakStartMin: nil)))            // no typical start
    }

    // JS: at − live.in > 12h (strict).
    func testForgotClockOut() {
        let live = openWorkSession(date(2026, 7, 15, 6, 0))
        XCTAssertTrue(Engine.forgotClockOut(live: live, at: date(2026, 7, 15, 18, 0, 1)))   // 12h + 1s
        XCTAssertFalse(Engine.forgotClockOut(live: live, at: date(2026, 7, 15, 18, 0, 0)))  // exactly 12h
        XCTAssertFalse(Engine.forgotClockOut(live: live, at: date(2026, 7, 15, 17, 59)))    // 11h 59m
        XCTAssertFalse(Engine.forgotClockOut(live: nil, at: anchorNoon))
    }
}
