import XCTest
@testable import Clocked

/// The views now fetch date-bounded slices instead of lifetime history, and
/// range aggregation groups sessions by day in one pass. These pin that the
/// bounded/grouped paths return exactly what the unbounded ones did.
@MainActor
final class BoundedFetchTests: XCTestCase {

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        return Calendar.current.date(from: c)!
    }

    private func addShift(_ store: TrackerStore, in inD: Date, out: Date) {
        store.clockIn(at: inD)
        store.clockOut(at: out)
    }

    func testCompletedShiftsBoundedFetch() {
        let store = TrackerStore(inMemory: true)
        addShift(store, in: date(2026, 6, 1, 9, 0), out: date(2026, 6, 1, 17, 0))   // before range
        addShift(store, in: date(2026, 7, 13, 9, 0), out: date(2026, 7, 13, 17, 0)) // in range
        addShift(store, in: date(2026, 7, 15, 9, 0), out: date(2026, 7, 15, 12, 0)) // in range
        addShift(store, in: date(2026, 7, 20, 9, 0), out: date(2026, 7, 20, 17, 0)) // at `to` → excluded

        let from = date(2026, 7, 13, 0, 0)
        let to = date(2026, 7, 20, 9, 0)
        let fetched = store.completedShifts(from: from, to: to)
        XCTAssertEqual(fetched.count, 2)
        XCTAssertEqual(fetched.map(\.clockIn), [date(2026, 7, 13, 9, 0), date(2026, 7, 15, 9, 0)])
        // Unbounded still sees everything.
        XCTAssertEqual(store.completedShifts.count, 4)
    }

    func testAllSnapshotsIncludesLiveOnlyWhenClockInInRange() {
        let store = TrackerStore(inMemory: true)
        addShift(store, in: date(2026, 7, 14, 9, 0), out: date(2026, 7, 14, 17, 0))
        store.clockIn(at: date(2026, 7, 15, 9, 0))  // live

        let weekFrom = date(2026, 7, 13, 0, 0), weekTo = date(2026, 7, 20, 0, 0)
        XCTAssertEqual(store.allSnapshots(from: weekFrom, to: weekTo).count, 2)
        XCTAssertTrue(store.allSnapshots(from: weekFrom, to: weekTo).contains(where: \.isLive))
        // Live clock-in outside the range → excluded (day attribution follows clockIn).
        let nextWeek = date(2026, 7, 20, 0, 0)
        XCTAssertTrue(store.allSnapshots(from: nextWeek, to: date(2026, 7, 27, 0, 0)).isEmpty)
    }

    /// totalsByDay must agree with per-day dayTotals on every field, for every
    /// day of a mixed fixture (multi-session day, break day, live session).
    func testTotalsByDayMatchesPerDayTotals() {
        let cal = Calendar.current
        let at = date(2026, 7, 15, 20, 0)
        var sessions: [SessionSnapshot] = []
        // Two sessions on the 13th, one with a break on the 14th, live on the 15th.
        sessions.append(SessionSnapshot(
            clockIn: date(2026, 7, 13, 9, 0), clockOut: date(2026, 7, 13, 12, 0),
            segments: [SegmentSnapshot(isBreak: false, start: date(2026, 7, 13, 9, 0), end: date(2026, 7, 13, 12, 0))]))
        sessions.append(SessionSnapshot(
            clockIn: date(2026, 7, 13, 14, 0), clockOut: date(2026, 7, 13, 17, 0),
            segments: [SegmentSnapshot(isBreak: false, start: date(2026, 7, 13, 14, 0), end: date(2026, 7, 13, 17, 0))]))
        sessions.append(SessionSnapshot(
            clockIn: date(2026, 7, 14, 9, 0), clockOut: date(2026, 7, 14, 17, 0),
            segments: [
                SegmentSnapshot(isBreak: false, start: date(2026, 7, 14, 9, 0), end: date(2026, 7, 14, 12, 0)),
                SegmentSnapshot(isBreak: true, start: date(2026, 7, 14, 12, 0), end: date(2026, 7, 14, 13, 0)),
                SegmentSnapshot(isBreak: false, start: date(2026, 7, 14, 13, 0), end: date(2026, 7, 14, 17, 0)),
            ]))
        sessions.append(SessionSnapshot(
            clockIn: date(2026, 7, 15, 9, 0), clockOut: nil,
            segments: [SegmentSnapshot(isBreak: false, start: date(2026, 7, 15, 9, 0), end: nil)]))

        let byDay = Engine.totalsByDay(sessions: sessions, at: at, calendar: cal)
        for offset in 0...3 {
            let day = TimeMath.addDays(date(2026, 7, 12, 12, 0), offset, calendar: cal)
            let direct = Engine.dayTotals(on: day, sessions: sessions, at: at, calendar: cal)
            let grouped = byDay[TimeMath.dayKey(day, calendar: cal)] ?? DayTotals()
            XCTAssertEqual(grouped.work, direct.work, "work mismatch day +\(offset)")
            XCTAssertEqual(grouped.brk, direct.brk, "break mismatch day +\(offset)")
            XCTAssertEqual(grouped.first, direct.first, "first mismatch day +\(offset)")
            XCTAssertEqual(grouped.last, direct.last, "last mismatch day +\(offset)")
            XCTAssertEqual(grouped.sessionCount, direct.sessionCount, "count mismatch day +\(offset)")
        }
        // rangeTotals (now grouped internally) over the whole span.
        let tot = Engine.rangeTotals(from: date(2026, 7, 13, 0, 0), to: date(2026, 7, 16, 0, 0),
                                     sessions: sessions, at: at, calendar: cal)
        let expectedWork: TimeInterval = (6 + 7 + 11) * 3600        // 3+3, 7, 11h live
        let expectedBreak: TimeInterval = 3600
        XCTAssertEqual(tot.work, expectedWork)
        XCTAssertEqual(tot.brk, expectedBreak)
        XCTAssertEqual(tot.daysWithPaid, 3)
    }
}
