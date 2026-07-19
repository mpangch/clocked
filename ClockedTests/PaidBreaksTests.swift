import XCTest
@testable import Clocked

/// Paid-breaks revision: in-shift breaks are paid (paid = work + breaks);
/// unpaid pauses are clock-outs, so several sessions per day must work and
/// sum per day with the gaps between them excluded.
@MainActor
final class PaidBreaksTests: XCTestCase {

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        return Calendar.current.date(from: c)!
    }

    func testPaidDurationIncludesBreaks() {
        let s = SessionSnapshot(
            clockIn: date(2026, 7, 15, 9, 0), clockOut: date(2026, 7, 15, 17, 0),
            segments: [
                SegmentSnapshot(isBreak: false, start: date(2026, 7, 15, 9, 0), end: date(2026, 7, 15, 12, 0)),
                SegmentSnapshot(isBreak: true, start: date(2026, 7, 15, 12, 0), end: date(2026, 7, 15, 13, 0)),
                SegmentSnapshot(isBreak: false, start: date(2026, 7, 15, 13, 0), end: date(2026, 7, 15, 17, 0)),
            ])
        let at = date(2026, 7, 15, 18, 0)
        XCTAssertEqual(Engine.workDuration(s, at: at), 7 * 3600)
        XCTAssertEqual(Engine.breakDuration(s, at: at), 3600)
        XCTAssertEqual(Engine.paidDuration(s, at: at), 8 * 3600)   // clock-in → clock-out
    }

    /// Clock in and out three times in one day: three sessions exist, the day
    /// sums their paid time, and the unpaid gaps between them count nothing.
    func testMultipleSessionsPerDay() {
        let store = TrackerStore(inMemory: true)
        // Morning 8–11, unpaid lunch gap, afternoon 12:30–15:30 with a 30m
        // paid break, evening 17–18.
        store.clockIn(at: date(2026, 7, 15, 8, 0))
        store.clockOut(at: date(2026, 7, 15, 11, 0))
        store.clockIn(at: date(2026, 7, 15, 12, 30))
        store.startBreak(at: date(2026, 7, 15, 13, 30))
        store.resumeWork(at: date(2026, 7, 15, 14, 0))
        store.clockOut(at: date(2026, 7, 15, 15, 30))
        store.clockIn(at: date(2026, 7, 15, 17, 0))
        store.clockOut(at: date(2026, 7, 15, 18, 0))

        XCTAssertEqual(store.completedShifts.count, 3)
        XCTAssertNil(store.liveShift)   // nothing left open

        let at = date(2026, 7, 15, 19, 0)
        let t = Engine.dayTotals(on: date(2026, 7, 15, 12, 0),
                                 sessions: store.allSnapshots, at: at)
        XCTAssertEqual(t.sessionCount, 3)
        XCTAssertEqual(t.paid, (3 + 3 + 1) * 3600)      // 8h span minus the gaps
        XCTAssertEqual(t.brk, 1800)                     // the paid break, reported
        XCTAssertEqual(t.first, date(2026, 7, 15, 8, 0))
        XCTAssertEqual(t.last, date(2026, 7, 15, 18, 0))

        // Weekly goal math sees the same paid total.
        XCTAssertEqual(Engine.weekPaid(sessions: store.allSnapshots, at: at), 7 * 3600)
    }

    /// Days whose only paid time is break time still count toward Avg/day —
    /// the counter follows paid hours, not just work segments.
    func testBreakOnlyDayCountsAsPaidDay() {
        let sessions = [SessionSnapshot(
            clockIn: date(2026, 7, 15, 9, 0), clockOut: date(2026, 7, 15, 9, 30),
            segments: [
                SegmentSnapshot(isBreak: false, start: date(2026, 7, 15, 9, 0), end: date(2026, 7, 15, 9, 0)),
                SegmentSnapshot(isBreak: true, start: date(2026, 7, 15, 9, 0), end: date(2026, 7, 15, 9, 30)),
            ])]
        let t = Engine.rangeTotals(from: date(2026, 7, 13, 0, 0), to: date(2026, 7, 20, 0, 0),
                                   sessions: sessions, at: date(2026, 7, 15, 10, 0))
        XCTAssertEqual(t.work, 0)
        XCTAssertEqual(t.paid, 1800)
        XCTAssertEqual(t.daysWithPaid, 1)
    }

    /// A fourth clock-in on the same day works immediately after a clock-out
    /// (the only guard is against a second LIVE shift).
    func testReClockInAfterClockOut() {
        let store = TrackerStore(inMemory: true)
        store.clockIn(at: date(2026, 7, 15, 9, 0))
        store.clockIn(at: date(2026, 7, 15, 9, 5))      // ignored: already live
        XCTAssertEqual(store.completedShifts.count + (store.liveShift == nil ? 0 : 1), 1)
        store.clockOut(at: date(2026, 7, 15, 10, 0))
        store.clockIn(at: date(2026, 7, 15, 10, 1))     // one minute later: fine
        XCTAssertNotNil(store.liveShift)
        XCTAssertEqual(store.completedShifts.count, 1)
    }
}
