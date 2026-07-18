import XCTest
@testable import Clocked

/// CSV backup: export → parse → import must reconstruct the same shifts, and
/// re-importing must be a no-op (reinstalls/sideload overwrites drop the store,
/// so this is the data-safety path).
@MainActor
final class BackupRoundTripTests: XCTestCase {

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ sec: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi; c.second = sec
        return Calendar.current.date(from: c)!
    }

    func testExportParseRoundTripPreservesBreakTiming() {
        let sessions = [
            SessionSnapshot(
                clockIn: date(2026, 7, 13, 9, 0), clockOut: date(2026, 7, 13, 16, 0),
                segments: [
                    SegmentSnapshot(isBreak: false, start: date(2026, 7, 13, 9, 0), end: date(2026, 7, 13, 11, 15)),
                    SegmentSnapshot(isBreak: true, start: date(2026, 7, 13, 11, 15), end: date(2026, 7, 13, 12, 0)),
                    SegmentSnapshot(isBreak: false, start: date(2026, 7, 13, 12, 0), end: date(2026, 7, 13, 16, 0)),
                ]),
            SessionSnapshot(
                clockIn: date(2026, 7, 14, 8, 30), clockOut: date(2026, 7, 14, 15, 0),
                segments: [SegmentSnapshot(isBreak: false, start: date(2026, 7, 14, 8, 30), end: date(2026, 7, 14, 15, 0))]),
        ]
        let csv = Engine.csv(history: sessions, live: nil,
                             from: .distantPast, to: .distantFuture, at: date(2026, 7, 15, 12, 0))
        let parsed = Engine.parseCSVBackup(csv)
        XCTAssertEqual(parsed.skippedRows, 0)
        XCTAssertEqual(parsed.shifts.count, 2)
        // The break comes back at 11:15–12:00, not centered.
        let first = parsed.shifts[0]
        XCTAssertEqual(first.clockIn, date(2026, 7, 13, 9, 0))
        XCTAssertEqual(first.clockOut, date(2026, 7, 13, 16, 0))
        XCTAssertEqual(first.segments.count, 3)
        XCTAssertEqual(first.segments[1].isBreak, true)
        XCTAssertEqual(first.segments[1].start, date(2026, 7, 13, 11, 15))
        XCTAssertEqual(first.segments[1].end, date(2026, 7, 13, 12, 0))
        // Break-free shift stays one segment.
        XCTAssertEqual(parsed.shifts[1].segments.count, 1)
    }

    func testLegacyHeaderAndMissingBreakStartCenterTheBreak() {
        let csv = """
        date,clock_in,clock_out,break_minutes,net_hours
        2026-07-14,11:00,18:00,60,6.00
        total,,,,6.00
        """
        let parsed = Engine.parseCSVBackup(csv)
        XCTAssertEqual(parsed.shifts.count, 1)
        let s = parsed.shifts[0]
        // Centered like Add Entry: offset = round((420 − 60) / 2) = 180 → 14:00.
        XCTAssertEqual(s.segments[1].start, date(2026, 7, 14, 14, 0))
        XCTAssertEqual(s.segments[1].end, date(2026, 7, 14, 15, 0))
    }

    func testOvernightActiveTotalAndMalformedRows() {
        let csv = """
        date,clock_in,clock_out,break_minutes,break_start,paid_hours
        2026-07-13,23:30,01:30,0,,2.00
        2026-07-14,09:00,(active),0,,1.50
        garbage line
        2026-07-15,25:99,17:00,0,,8.00
        total,,,,,3.50
        """
        let parsed = Engine.parseCSVBackup(csv)
        XCTAssertEqual(parsed.shifts.count, 1)               // only the overnight row
        XCTAssertEqual(parsed.skippedRows, 2)                // garbage + bad time
        let s = parsed.shifts[0]
        XCTAssertEqual(s.clockIn, date(2026, 7, 13, 23, 30))
        XCTAssertEqual(s.clockOut, date(2026, 7, 14, 1, 30)) // crossed midnight
    }

    func testInvalidBreakStartFallsBackToCenteredAndBreakIsClamped() {
        let csv = """
        date,clock_in,clock_out,break_minutes,break_start,paid_hours
        2026-07-14,09:00,10:00,15,20:00,1.00
        2026-07-15,09:00,10:00,90,,1.00
        """
        let parsed = Engine.parseCSVBackup(csv)
        XCTAssertEqual(parsed.shifts.count, 2)
        // 20:00 is outside 9–10 → centered: offset round((60−15)/2) = 23 → 9:23.
        XCTAssertEqual(parsed.shifts[0].segments[1].start, date(2026, 7, 14, 9, 23))
        // 90m break inside a 60m shift clamps to span − 2 = 58m.
        let clamped = parsed.shifts[1].segments[1]
        XCTAssertEqual(clamped.end!.timeIntervalSince(clamped.start), 58 * 60)
    }

    func testImportDedupesOnClockInMinute() {
        let store = TrackerStore(inMemory: true)
        // Existing shift recorded with seconds — its CSV row reads 09:00.
        store.clockIn(at: date(2026, 7, 13, 9, 0, 23))
        store.clockOut(at: date(2026, 7, 13, 16, 0, 40))

        let csv = """
        date,clock_in,clock_out,break_minutes,break_start,paid_hours
        2026-07-13,09:00,16:00,0,,7.00
        2026-07-14,09:00,17:00,0,,8.00
        """
        let parsed = Engine.parseCSVBackup(csv)
        let first = store.importShifts(parsed.shifts)
        XCTAssertEqual(first.inserted, 1)                    // only the 14th is new
        XCTAssertEqual(first.duplicates, 1)                  // 13th matched by minute
        XCTAssertEqual(store.completedShifts.count, 2)

        // Re-importing the same backup is a no-op.
        let second = store.importShifts(parsed.shifts)
        XCTAssertEqual(second.inserted, 0)
        XCTAssertEqual(second.duplicates, 2)
        XCTAssertEqual(store.completedShifts.count, 2)
    }

    func testFullRoundTripThroughStore() {
        let source = TrackerStore(inMemory: true)
        source.clockIn(at: date(2026, 7, 13, 9, 0))
        source.startBreak(at: date(2026, 7, 13, 12, 0))
        source.resumeWork(at: date(2026, 7, 13, 12, 30))
        source.clockOut(at: date(2026, 7, 13, 16, 0))
        source.clockIn(at: date(2026, 7, 14, 10, 0))
        source.clockOut(at: date(2026, 7, 14, 14, 0))

        let backup = Engine.csv(history: source.historySnapshots, live: nil,
                                from: .distantPast, to: .distantFuture, at: date(2026, 7, 15, 12, 0))

        let restored = TrackerStore(inMemory: true)
        let outcome = restored.importShifts(Engine.parseCSVBackup(backup).shifts)
        XCTAssertEqual(outcome.inserted, 2)
        XCTAssertEqual(outcome.duplicates, 0)

        let at = date(2026, 7, 15, 12, 0)
        let a = Engine.totalsByDay(sessions: source.allSnapshots, at: at)
        let b = Engine.totalsByDay(sessions: restored.allSnapshots, at: at)
        XCTAssertEqual(a.keys.sorted(), b.keys.sorted())
        for key in a.keys {
            XCTAssertEqual(a[key]?.paid, b[key]?.paid, "paid mismatch \(key)")
            XCTAssertEqual(a[key]?.brk, b[key]?.brk, "break mismatch \(key)")
        }
    }
}
