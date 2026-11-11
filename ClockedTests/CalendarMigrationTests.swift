import XCTest
@testable import Clocked

final class CalendarMigrationTests: XCTestCase {
    func testManualEntryKeepsWallTimesOnBothDSTChangeDays() {
        for (month, day) in [(3, 8), (11, 1)] {
            let segments = Engine.manualEntrySegments(
                dayStart: date(2026, month, day),
                draft: AddEntryDraft(inMin: 9 * 60, outMin: 17 * 60, breakMin: 30),
                calendar: testCal)
            XCTAssertEqual(segments.first?.start, date(2026, month, day, 9))
            XCTAssertEqual(segments.last?.end, date(2026, month, day, 17))
            XCTAssertEqual(segments.reduce(0) { $0 + Engine.segDuration($1, at: anchorNoon) }, 8 * 3600)
        }
    }

    func testManualEntryAcrossDSTUsesElapsedPaidTime() {
        for (month, day, hours) in [(3, 8, 3), (11, 1, 5)] {
            let segments = Engine.manualEntrySegments(
                dayStart: date(2026, month, day),
                draft: AddEntryDraft(inMin: 0, outMin: 4 * 60, breakMin: 30),
                calendar: testCal)
            XCTAssertEqual(segments.count, 3)
            XCTAssertEqual(segments.reduce(0) { $0 + Engine.segDuration($1, at: anchorNoon) }, Double(hours * 3600))
            if segments.count == 3 {
                XCTAssertEqual(Engine.segDuration(segments[0], at: anchorNoon),
                               Engine.segDuration(segments[2], at: anchorNoon))
            }
        }
    }

    func testNonexistentSpringClockReadingIsRejected() {
        XCTAssertNil(TimeMath.wallClockTime(2 * 60 + 30, on: date(2026, 3, 8), calendar: testCal))
        XCTAssertTrue(Engine.manualEntrySegments(
            dayStart: date(2026, 3, 8),
            draft: AddEntryDraft(inMin: 2 * 60 + 30, outMin: 4 * 60, breakMin: 0),
            calendar: testCal).isEmpty)
        let parsed = Engine.parseCSVBackup(
            "date,clock_in,clock_out\n2026-03-08,02:30,04:00", calendar: testCal)
        XCTAssertTrue(parsed.shifts.isEmpty)
        XCTAssertEqual(parsed.skippedRows, 1)
    }

    func testTooShortElapsedShiftOrOversizedBreakIsRejected() {
        for draft in [AddEntryDraft(inMin: 105, outMin: 180, breakMin: 0),
                      AddEntryDraft(inMin: 60, outMin: 240, breakMin: 120)] {
            XCTAssertTrue(Engine.manualEntrySegments(dayStart: date(2026, 3, 8),
                                                     draft: draft, calendar: testCal).isEmpty)
        }
    }

    func testBackupPreservesBreakWallTimeAcrossDST() throws {
        for (month, day) in [(3, 8), (11, 1)] {
            let original = sessionWithBreak(date(2026, month, day), date(2026, month, day, 8),
                                            breakStart: date(2026, month, day, 4),
                                            breakEnd: date(2026, month, day, 4, 30))
            let csv = Engine.csv(history: [original], live: nil, from: .distantPast,
                                 to: .distantFuture, at: anchorNoon, calendar: testCal)
            let restored = try XCTUnwrap(Engine.parseCSVBackup(csv, calendar: testCal).shifts.first)
            XCTAssertEqual(restored.segments, original.segments)
        }
    }

    func testOvernightBackupPreservesBreakAfterDSTChange() throws {
        let original = sessionWithBreak(date(2026, 10, 31, 23), date(2026, 11, 1, 8),
                                        breakStart: date(2026, 11, 1, 4), breakEnd: date(2026, 11, 1, 4, 30))
        let csv = Engine.csv(history: [original], live: nil, from: .distantPast,
                             to: .distantFuture, at: anchorNoon, calendar: testCal)
        let restored = try XCTUnwrap(Engine.parseCSVBackup(csv, calendar: testCal).shifts.first)
        XCTAssertEqual(restored.segments, original.segments)
    }

    func testMalformedDatesAreSkippedInsteadOfNormalized() {
        let invalidDates = ["2026-02-30", "2026-13-01", "2026-00-15", "2026-07-00",
                            "2026-07-32", "2026--07-15", "2026-junk-07-15", "-2026-07-15"]
        let csv = "date,clock_in,clock_out\n" + invalidDates.map { "\($0),09:00,17:00" }.joined(separator: "\n")
        let parsed = Engine.parseCSVBackup(csv, calendar: testCal)
        XCTAssertTrue(parsed.shifts.isEmpty)
        XCTAssertEqual(parsed.skippedRows, invalidDates.count)
    }

    func testLeapDayAndUTF8BOMAreAccepted() throws {
        let csv = "\u{FEFF}date,clock_in,clock_out\n2024-02-29,09:00,17:00\n2026-02-29,09:00,17:00"
        let parsed = Engine.parseCSVBackup(csv, calendar: testCal)
        XCTAssertEqual(parsed.shifts.count, 1)
        XCTAssertEqual(try XCTUnwrap(parsed.shifts.first).clockIn, date(2024, 2, 29, 9))
        XCTAssertEqual(parsed.skippedRows, 1)
    }

    func testMalformedTimeSeparatorsAreRejected() {
        let parsed = Engine.parseCSVBackup("date,clock_in,clock_out\n2026-07-15,09::00,17:00", calendar: testCal)
        XCTAssertTrue(parsed.shifts.isEmpty)
        XCTAssertEqual(parsed.skippedRows, 1)
    }
}
